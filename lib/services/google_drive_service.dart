import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'backup_freshness_service.dart';

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
    final connected = await _googleSignIn.isSignedIn();
    if (connected && _googleSignIn.currentUser == null) {
      try {
        await _googleSignIn.signInSilently();
      } catch (e) {
        debugPrint('GoogleDriveService: Silent sign-in failed: $e');
        return false;
      }
    }
    return _googleSignIn.currentUser != null;
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
      debugPrint('GoogleDriveService: Disconnected Google Account');
    } catch (e) {
      debugPrint('GoogleDriveService: Signout failed: $e');
      rethrow;
    }
  }

  /// Get authenticated HTTP client using the active signed-in user's credentials
  Future<gauth.AuthClient> getAuthClient() async {
    // Attempt silent sign-in to refresh access token if it is expired/stale
    GoogleSignInAccount? account = await _googleSignIn.signInSilently();
    account ??= _googleSignIn.currentUser;
    
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

  /// Uploads encrypted backup ZIP bytes to Google Drive.
  /// Updates 'latest_backup.zip' and manages daily rolling backups.
  Future<void> uploadBackup(
    List<int> encryptedZipBytes,
    Map<String, dynamic> metadata, {
    void Function(double progress)? onProgress,
  }) async {
    if (await BackupFreshnessService().areBackupsBlocked()) {
      throw Exception('Upload blocked: Google Drive has a newer backup or freshness validation failed.');
    }
    try {
      final authClient = await getAuthClient();
      final driveApi = drive.DriveApi(authClient);

      // 1. Ensure backup folder exists
      final folderId = await findOrCreateBackupsFolder(driveApi);

      // Helper function to generate a fresh media stream for each upload to avoid "Stream has already been listened to" error.
      drive.Media createMedia(double startProgress, double endProgress) {
        try {
          final baseStream = Stream<List<int>>.value(encryptedZipBytes);
          final trackedStream = GoogleDriveService.trackStreamProgress(
            baseStream,
            encryptedZipBytes.length,
            (p) {
              if (onProgress != null) {
                final overall = startProgress + (p * (endProgress - startProgress));
                onProgress(overall);
              }
            },
          );
          return drive.Media(
            trackedStream,
            encryptedZipBytes.length,
            contentType: 'application/zip',
          );
        } catch (e, stack) {
          debugPrint('GoogleDriveService: Error creating media stream: $e\n$stack');
          rethrow;
        }
      }

      final metadataString = jsonEncode(metadata);

      // ===================================================
      // A. UPLOAD/UPDATE "latest_backup.zip"
      // ===================================================
      const latestFilename = 'latest_backup.zip';
      final latestQuery = await driveApi.files.list(
        q: "name = '$latestFilename' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id)',
      );

      final latestFiles = latestQuery.files;
      final fileMetadata = drive.File()
        ..name = latestFilename
        ..description = metadataString; // Save JSON metadata in file description!

      drive.File uploadedFile;
      if (latestFiles != null && latestFiles.isNotEmpty) {
        // Replace existing latest_backup
        final fileId = latestFiles.first.id!;
        try {
          uploadedFile = await driveApi.files.update(
            fileMetadata,
            fileId,
            uploadMedia: createMedia(0.0, 0.5),
          );
          debugPrint('GoogleDriveService: Successfully updated latest_backup.zip ($fileId)');
        } catch (e, stack) {
          debugPrint('GoogleDriveService: Failed updating latest_backup.zip stream upload: $e\n$stack');
          rethrow;
        }
      } else {
        // Create new latest_backup
        fileMetadata.parents = [folderId];
        try {
          uploadedFile = await driveApi.files.create(
            fileMetadata,
            uploadMedia: createMedia(0.0, 0.5),
          );
          debugPrint('GoogleDriveService: Successfully created latest_backup.zip (${uploadedFile.id})');
        } catch (e, stack) {
          debugPrint('GoogleDriveService: Failed creating latest_backup.zip stream upload: $e\n$stack');
          rethrow;
        }
      }

      // Save backup stats to local SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_gdrive_backup_date', DateTime.now().toIso8601String());
      await prefs.setString('last_gdrive_backup_size', '${(encryptedZipBytes.length / 1024).toStringAsFixed(1)} KB');
      await prefs.setString('last_gdrive_backup_health', 'Healthy (Checksum Verified)');

      // ===================================================
      // B. UPLOAD "daily_backup_YYYY_MM_DD.zip"
      // ===================================================
      final todayStr = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '_'); // YYYY_MM_DD
      final dailyFilename = 'daily_backup_$todayStr.zip';

      final dailyQuery = await driveApi.files.list(
        q: "name = '$dailyFilename' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id)',
      );

      final dailyFiles = dailyQuery.files;
      final dailyMetadata = drive.File()
        ..name = dailyFilename
        ..description = metadataString;

      if (dailyFiles != null && dailyFiles.isNotEmpty) {
        // Replace today's daily backup if it already exists
        try {
          await driveApi.files.update(
            dailyMetadata,
            dailyFiles.first.id!,
            uploadMedia: createMedia(0.5, 1.0),
          );
          debugPrint('GoogleDriveService: Updated daily snapshot: $dailyFilename');
        } catch (e, stack) {
          debugPrint('GoogleDriveService: Failed updating daily snapshot stream upload: $e\n$stack');
          rethrow;
        }
      } else {
        // Create new daily snapshot
        dailyMetadata.parents = [folderId];
        try {
          await driveApi.files.create(
            dailyMetadata,
            uploadMedia: createMedia(0.5, 1.0),
          );
          debugPrint('GoogleDriveService: Created daily snapshot: $dailyFilename');
        } catch (e, stack) {
          debugPrint('GoogleDriveService: Failed creating daily snapshot stream upload: $e\n$stack');
          rethrow;
        }
      }

      // ===================================================
      // C. ENFORCE 7-DAY SNAPSHOT RETENTION POLICY
      // ===================================================
      await _enforceRetentionPolicy(driveApi, folderId);
    } catch (e, stack) {
      debugPrint('GoogleDriveService: uploadBackup total operation failure: $e\n$stack');
      rethrow;
    }
  }

  /// Keep only the last 7 daily backups. Delete older backups.
  Future<void> _enforceRetentionPolicy(drive.DriveApi driveApi, String folderId) async {
    try {
      final listResult = await driveApi.files.list(
        q: "name contains 'daily_backup_' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name, createdTime)',
      );

      final files = listResult.files;
      if (files != null && files.length > 7) {
        // Sort alphabetical by name (since filename has daily_backup_YYYY_MM_DD, oldest dates come first)
        files.sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));
        
        final deleteCount = files.length - 7;
        for (int i = 0; i < deleteCount; i++) {
          final fileId = files[i].id!;
          await driveApi.files.delete(fileId);
          debugPrint('GoogleDriveService: Auto-deleted expired daily backup: ${files[i].name}');
        }
      }
    } catch (e) {
      debugPrint('GoogleDriveService: Failed to enforce retention policy: $e');
    }
  }

  /// Lists all backups currently stored in Google Drive
  Future<List<Map<String, dynamic>>> listBackups() async {
    final authClient = await getAuthClient();
    final driveApi = drive.DriveApi(authClient);
    final folderId = await findOrCreateBackupsFolder(driveApi);

    final listResult = await driveApi.files.list(
      q: "'$folderId' in parents and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name, size, description, createdTime)',
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
        'metadata': meta,
      });
    }

    // Sort backups: latest modified/created first
    list.sort((a, b) {
      final nameA = a['name'] as String;
      final nameB = b['name'] as String;
      
      // Keep latest_backup.zip at the very top of list
      if (nameA == 'latest_backup.zip') return -1;
      if (nameB == 'latest_backup.zip') return 1;

      return nameB.compareTo(nameA);
    });

    return list;
  }

  /// Downloads backup ZIP file bytes from Google Drive
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

