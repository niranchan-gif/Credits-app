import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.file',
    ],
  );

  /// Get current signed-in Google account
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  /// Check if the user is connected
  Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('google_drive_account_email');
    if (email != null && email.isNotEmpty) {
      // Start silent sign in in the background to refresh tokens, but return true instantly
      _googleSignIn.signInSilently().catchError((_) => null);
      return true;
    }

    final connected = await _googleSignIn.isSignedIn();
    if (connected && _googleSignIn.currentUser == null) {
      try {
        await _googleSignIn.signInSilently();
      } catch (e) {
        debugPrint('GoogleDriveService: Silent sign-in failed: $e');
      }
    }
    
    return _googleSignIn.currentUser != null || connected;
  }

  /// Connect Google Account (triggers login flow)
  Future<GoogleSignInAccount?> connectAccount() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('google_drive_account_email', account.email);
        debugPrint('GoogleDriveService: Connected account: ${account.email}');
      }
      return account;
    } catch (e) {
      debugPrint('GoogleDriveService: Connection failed: $e');
      rethrow;
    }
  }

  /// Disconnect Google Account (signs out)
  Future<void> disconnectAccount() async {
    try {
      await _googleSignIn.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('google_drive_account_email');
      await prefs.remove('last_gdrive_backup_date');
      await prefs.remove('last_gdrive_backup_size');
      await prefs.remove('last_gdrive_backup_health');
      await prefs.remove('google_drive_excel_backup_file_id');
      await prefs.remove('last_excel_backup_checksum');
      debugPrint('GoogleDriveService: Account disconnected.');
    } catch (e) {
      debugPrint('GoogleDriveService: Disconnect failed: $e');
      rethrow;
    }
  }

  /// Get authenticated HTTP client using the active signed-in user's credentials
  Future<gauth.AuthClient> getAuthClient() async {
    // Attempt silent sign-in to refresh access token if it is expired/stale
    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signInSilently();
    } catch (e) {
      debugPrint('GoogleDriveService: Silent sign-in error in getAuthClient: $e');
    }
    account ??= _googleSignIn.currentUser;
    
    if (account == null) {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('google_drive_account_email');
      if (email != null && email.isNotEmpty) {
        try {
          account = await _googleSignIn.signIn();
        } catch (e) {
          debugPrint('GoogleDriveService: Interactive fallback sign-in failed: $e');
        }
      }
    }
    
    if (account == null) {
      throw Exception('User is not signed in to a Google account.');
    }

    final auth = await account.authentication;
    final accessToken = auth.accessToken;
    if (accessToken == null) {
      throw Exception('Failed to obtain Google access token.');
    }

    final credentials = gauth.AccessCredentials(
      gauth.AccessToken(
        'Bearer',
        accessToken,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null, // Refresh token is managed automatically by google_sign_in package
      ['https://www.googleapis.com/auth/drive.file'],
    );

    return gauth.authenticatedClient(http.Client(), credentials);
  }

  /// Find or create the app backup folder `CreditsAppBackups` on Google Drive.
  /// Returns the Folder ID.
  Future<String> findOrCreateBackupsFolder(drive.DriveApi driveApi) async {
    const folderName = 'CreditsAppBackups';
    
    // 1. Search for existing folder
    final listResult = await driveApi.files.list(
      q: "name = '$folderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id)',
    );

    final files = listResult.files;
    if (files != null && files.isNotEmpty) {
      return files.first.id!;
    }

    // 2. Folder does not exist: create it
    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder';

    final createdFolder = await driveApi.files.create(folder);
    debugPrint('GoogleDriveService: Created folder $folderName with ID ${createdFolder.id}');
    return createdFolder.id!;
  }

  /// Lists all backups currently stored in Google Drive
  Future<List<Map<String, dynamic>>> listBackups() async {
    final authClient = await getAuthClient();
    final driveApi = drive.DriveApi(authClient);
    final folderId = await findOrCreateBackupsFolder(driveApi);

    final listResult = await driveApi.files.list(
      q: "name contains 'credits_backup' and name contains '.xlsx' and '$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, size, description, createdTime, modifiedTime)',
    );

    final files = listResult.files;
    if (files == null) return [];

    final list = <Map<String, dynamic>>[];
    for (final file in files) {
      Map<String, dynamic> meta = {};
      if (file.description != null && file.description!.isNotEmpty) {
        try {
          meta = jsonDecode(file.description!) as Map<String, dynamic>;
        } catch (_) {}
      }

      list.add({
        'id': file.id,
        'name': file.name,
        'size': file.size != null ? '${(int.parse(file.size!) / 1024).toStringAsFixed(1)} KB' : 'Unknown',
        'createdTime': file.createdTime,
        'modifiedTime': file.modifiedTime,
        'metadata': meta,
      });
    }

    // Sort backups by name descending (latest date first)
    list.sort((a, b) => (b['name'] as String).compareTo(a['name'] as String));

    return list;
  }

  /// Downloads backup file bytes from Google Drive
  Future<List<int>> downloadBackup(
    String fileId, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final authClient = await getAuthClient();
      final driveApi = drive.DriveApi(authClient);

      int? totalBytes;
      try {
        final f = await driveApi.files.get(fileId, $fields: 'size') as drive.File;
        totalBytes = int.tryParse(f.size ?? '');
      } catch (_) {}

      final response = await driveApi.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      totalBytes ??= response.length;

      final bytes = <int>[];
      int downloadedBytes = 0;
      try {
        await for (final chunk in response.stream) {
          bytes.addAll(chunk);
          downloadedBytes += chunk.length;
          if (totalBytes != null && totalBytes > 0) {
            onProgress?.call((downloadedBytes / totalBytes).clamp(0.0, 1.0));
          }
        }
      } catch (streamError, stack) {
        debugPrint('GoogleDriveService: Error reading download stream: $streamError\n$stack');
        rethrow;
      }
      return bytes;
    } catch (e, stack) {
      debugPrint('GoogleDriveService: downloadBackup total operation failure: $e\n$stack');
      rethrow;
    }
  }

  /// Standard stream progress tracker helper to monitor bytes read/written
  static Stream<List<int>> trackStreamProgress(
    Stream<List<int>> source,
    int totalBytes,
    void Function(double progress)? onProgress,
  ) async* {
    int byteCount = 0;
    await for (final chunk in source) {
      byteCount += chunk.length;
      if (onProgress != null && totalBytes > 0) {
        onProgress((byteCount / totalBytes).clamp(0.0, 1.0));
      }
      yield chunk;
    }
  }
}

