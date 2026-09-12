import 'dart:convert';
import 'dart:io';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import 'backup_encryption_service.dart';
import 'google_drive_service.dart';
import 'google_drive_json_backup_service.dart';

class JsonRestoreService {
  static final JsonRestoreService _instance = JsonRestoreService._internal();
  factory JsonRestoreService() => _instance;
  JsonRestoreService._internal();

  Future<void> restoreFromDrive({
    void Function(double progress, String message)? onProgress,
  }) async {
    DBHelper.isRestoring = true;
    final currentUser = GoogleDriveService().currentUser;
    if (currentUser == null) throw Exception('No user signed in');

    try {
      onProgress?.call(0.05, 'Connecting to Google Drive...');
      final driveService = GoogleDriveService();
      final authClient = await driveService.getAuthClient();
      final driveApi = drive.DriveApi(authClient);

      onProgress?.call(0.10, 'Locating backup folder...');
      final folderResult = await driveApi.files.list(
        q: "name = '${GoogleDriveJsonBackupService.backupFolderName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id)',
      );
      if (folderResult.files == null || folderResult.files!.isEmpty) {
        throw Exception('Backup folder not found on Google Drive.');
      }
      final folderId = folderResult.files!.first.id!;

      onProgress?.call(0.15, 'Finding backup file...');
      final fileList = await driveApi.files.list(
        q: "parents in '$folderId' and name='${GoogleDriveJsonBackupService.backupFileName}' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        throw Exception('Backup file not found in Google Drive.');
      }

      onProgress?.call(0.20, 'Downloading encrypted backup...');
      final fileId = fileList.files!.first.id!;
      final media = await driveApi.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
      
      final bytes = <int>[];
      await for (var chunk in media.stream) {
        bytes.addAll(chunk);
      }
      
      if (bytes.isEmpty) throw Exception('Downloaded file is empty.');

      onProgress?.call(0.40, 'Decrypting backup...');
      final decryptedZipBytes = BackupEncryptionService.decryptBytes(bytes, currentUser.id);

      onProgress?.call(0.50, 'Decompressing data...');
      final decompressedBytes = gzip.decode(decryptedZipBytes);
      final jsonString = utf8.decode(decompressedBytes);
      final payload = jsonDecode(jsonString) as Map<String, dynamic>;

      if (payload['schemaVersion'] < 15) {
        throw Exception('Backup schema too old. Expected 15 or higher.');
      }
      
      onProgress?.call(0.55, 'Validating backup structure...');
      final data = payload['data'] as Map<String, dynamic>;
      final databasesDir = await getDatabasesPath();
      final tempDbPath = p.join(databasesDir, 'restore_temp_${DateTime.now().millisecondsSinceEpoch}.db');
      
      final dbHelper = DBHelper();
      final tempFile = File(tempDbPath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      for (final ext in ['-wal', '-shm', '-journal']) {
        final aux = File('$tempDbPath$ext');
        if (await aux.exists()) await aux.delete();
      }
      
      onProgress?.call(0.60, 'Creating validation database...');
      final tempDb = await dbHelper.createEmptyDatabase(tempDbPath);
      
      final tables = ['borrowers', 'loans', 'payments', 'investments', 'expenses', 'service_costs'];
      
      onProgress?.call(0.65, 'Importing data...');
      final batch = tempDb.batch();
      for (final table in tables) {
        if (data.containsKey(table)) {
          final rows = data[table] as List;
          for (final row in rows) {
            batch.insert(
              table,
              Map<String, dynamic>.from(row),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
      onProgress?.call(0.80, 'Writing data to database...');
      await batch.commit(noResult: true);
      
      onProgress?.call(0.87, 'Running integrity check...');
      final integrityCheck = await tempDb.rawQuery('PRAGMA integrity_check');
      if (integrityCheck.first.values.first != 'ok') {
        await tempDb.close();
        throw Exception('Database integrity check failed after importing JSON!');
      }
      
      try {
        await tempDb.rawQuery('PRAGMA wal_checkpoint(FULL)');
      } catch (_) {}

      await tempDb.close();

      onProgress?.call(0.90, 'Preparing database swap...');
      final currentDbPath = await dbHelper.getCurrentDbPath();
      await dbHelper.closeDatabase();
      
      final safetyCopyPath = '$currentDbPath.bak';
      if (await File(currentDbPath).exists()) {
        await File(currentDbPath).copy(safetyCopyPath);
      }
      
      onProgress?.call(0.95, 'Replacing database...');
      try {
        // Remove existing WAL, SHM, and journal files so old logs don't conflict
        for (final ext in ['-wal', '-shm', '-journal']) {
          final aux = File('$currentDbPath$ext');
          if (await aux.exists()) await aux.delete();
        }

        // Copy validated database to current path
        await File(tempDbPath).copy(currentDbPath);
      } catch (e) {
        if (await File(safetyCopyPath).exists()) {
          await File(safetyCopyPath).copy(currentDbPath);
        }
        throw Exception('Failed to replace database: $e');
      } finally {
        // Clean up temporary database files
        try {
          if (await tempFile.exists()) await tempFile.delete();
          for (final ext in ['-wal', '-shm', '-journal']) {
            final aux = File('$tempDbPath$ext');
            if (await aux.exists()) await aux.delete();
          }
        } catch (_) {}
      }
      
      onProgress?.call(0.98, 'Reopening database...');
      DBHelper.isRestoring = false;
      await dbHelper.database;
      onProgress?.call(1.0, 'Restore complete!');
      
    } finally {
      DBHelper.isRestoring = false;
    }
  }
}
