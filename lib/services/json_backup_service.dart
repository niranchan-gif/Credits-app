import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../database/db_helper.dart';
import 'google_drive_service.dart';
import 'backup_encryption_service.dart';
import 'google_drive_json_backup_service.dart';
import 'auto_backup_manager.dart';
import 'notification_service.dart';

class JsonBackupService {
  static final JsonBackupService _instance = JsonBackupService._internal();
  factory JsonBackupService() => _instance;
  JsonBackupService._internal();

  bool _isBackingUp = false;
  int _pendingGeneration = 0;

  void triggerBackup() {
    debugPrint('[BACKUP-DEBUG] JSON Backup worker started');
    
    if (_isBackingUp) {
      debugPrint('[BACKUP-DEBUG] Backup already in progress. Queueing next generation...');
      _pendingGeneration = DBHelper.databaseGeneration;
      return;
    }

    _isBackingUp = true;
    _runBackupLoop();
  }

  Future<void> _runBackupLoop() async {
    while (true) {
      final currentGen = DBHelper.databaseGeneration;
      _pendingGeneration = 0;
      
      try {
        await _performJsonBackup();
      } catch (e) {
        debugPrint('[BACKUP-DEBUG] JSON Backup failed: $e');
        AutoBackupManager.syncStatus.value = SyncStatus.failed;
      }
      
      if (_pendingGeneration <= currentGen) {
        break; // No new mutations while we were backing up
      }
    }
    
    _isBackingUp = false;
    debugPrint('[BACKUP-DEBUG] JSON Backup worker finished');
  }

  Future<void> _performJsonBackup() async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    
    debugPrint('[BACKUP-DEBUG] Extracting SQLite data to JSON...');
    AutoBackupManager.syncStatus.value = SyncStatus.syncing;
    

    final tables = ['borrowers', 'loans', 'payments', 'investments', 'expenses', 'service_costs'];
    final data = <String, List<Map<String, dynamic>>>{};
    final recordCounts = <String, int>{};
    
    for (var table in tables) {
      final rows = await db.query(table);
      data[table] = rows;
      recordCounts[table] = rows.length;
    }

    final currentUser = GoogleDriveService().currentUser;
    if (currentUser == null) throw Exception('No Google user signed in.');

    final jsonPayload = {
      'formatVersion': 1,
      'schemaVersion': 15,
      'installationId': 'credit_app',
      'backupGeneration': DBHelper.databaseGeneration,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'recordCounts': recordCounts,
      'data': data,
    };

    final jsonString = jsonEncode(jsonPayload);
    final jsonBytes = utf8.encode(jsonString);
    
    debugPrint('[BACKUP-DEBUG] Compressing JSON...');
    final compressedBytes = gzip.encode(jsonBytes);
    
    debugPrint('[BACKUP-DEBUG] Encrypting JSON backup...');
    final encryptedBytes = BackupEncryptionService.encryptBytes(compressedBytes, currentUser.id);

    final docDir = await getApplicationDocumentsDirectory();
    final localPath = p.join(docDir.path, GoogleDriveJsonBackupService.backupFileName);
    
    debugPrint('[BACKUP-DEBUG] Saving encrypted file locally: $localPath');
    final backupFile = File(localPath);
    await backupFile.writeAsBytes(encryptedBytes, flush: true);

    debugPrint('[BACKUP-DEBUG] Validating local backup size...');
    if (await backupFile.length() == 0) {
      throw Exception('Generated backup file is empty!');
    }

    debugPrint('[BACKUP-DEBUG] Uploading to Google Drive...');
    await GoogleDriveJsonBackupService().uploadJson(localPath);
    
    AutoBackupManager.syncStatus.value = SyncStatus.synced;
    NotificationService().showSyncSuccess();
    debugPrint('[BACKUP-DEBUG] Upload complete!');
  }
}
