import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as gauth;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_service.dart';

class GoogleDriveJsonBackupService {
  static final GoogleDriveJsonBackupService _instance = GoogleDriveJsonBackupService._internal();
  factory GoogleDriveJsonBackupService() => _instance;
  GoogleDriveJsonBackupService._internal();

  static const String backupFolderName = 'CreditsAppBackups';
  static const String backupFileName = 'credits_backup.json.enc';

  Future<String> _getOrCreateBackupFolderId(drive.DriveApi driveApi) async {
    final searchResult = await driveApi.files.list(
      q: "name = '$backupFolderName' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    if (searchResult.files != null && searchResult.files!.isNotEmpty) {
      return searchResult.files!.first.id!;
    }
    
    final folder = drive.File()
      ..name = backupFolderName
      ..mimeType = 'application/vnd.google-apps.folder';
      
    final createdFolder = await driveApi.files.create(folder);
    return createdFolder.id!;
  }

  Future<void> uploadJson(String localPath) async {
    final driveService = GoogleDriveService();
    final authClient = await driveService.getAuthClient();
    final driveApi = drive.DriveApi(authClient);
    final prefs = await SharedPreferences.getInstance();
    
    try {
      final folderId = await _getOrCreateBackupFolderId(driveApi);
      
      final searchResult = await driveApi.files.list(
        q: "parents in '$folderId' and name = '$backupFileName' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      
      final file = File(localPath);
      final media = drive.Media(file.openRead(), file.lengthSync());
      
      if (searchResult.files != null && searchResult.files!.isNotEmpty) {
        final existingFileId = searchResult.files!.first.id!;
        final driveFile = drive.File();
        await driveApi.files.update(driveFile, existingFileId, uploadMedia: media);
      } else {
        final driveFile = drive.File()
          ..name = backupFileName
          ..parents = [folderId];
        await driveApi.files.create(driveFile, uploadMedia: media);
      }
      
      await prefs.setBool('json_upload_pending', false);
      
      // Update local timestamp so it matches/exceeds the freshly created Drive file timestamp
      await prefs.setString('local_db_last_modified_timestamp', DateTime.now().toUtc().toIso8601String());
    } catch (e) {
      await prefs.setBool('json_upload_pending', true);
      throw Exception('Failed to upload JSON backup: $e');
    }
  }
}
