import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'encryption_service.dart';

class _EncryptionIsolateParams {
  final List<int> bytes;
  final String? email;
  _EncryptionIsolateParams(this.bytes, this.email);
}

class BackupService {
  static final DBHelper _dbHelper = DBHelper();

  /// Parameters for isolate-based encryption/decryption to prevent UI blocking
  static List<int> _encryptTask(_EncryptionIsolateParams params) => 
      EncryptionService.encryptBytes(params.bytes, email: params.email);

  /// Generates the database checksum (SHA256)
  static String calculateSHA256(List<int> bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Creates a ZIP archive containing the database, metadata, and optional Excel report.
  /// Returns in-memory ZIP bytes.
  static Future<List<int>> createFullDatabaseBackupBytes() async {
    debugPrint('BackupService: Starting full database backup bytes creation...');
    
    // 1. Get database instance and run checkpoint
    final db = await _dbHelper.database;
    debugPrint('BackupService: Executing PRAGMA wal_checkpoint(FULL)...');
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (e) {
      debugPrint('BackupService: WAL checkpoint failed: $e');
    }
    
    // 2. Locate database directory and files
    final dbPath = await getDatabasesPath();
    final Uint8List mainDbBytes;
    List<int>? walBytes;
    List<int>? shmBytes;

    final mainDbFile = File(join(dbPath, 'loan_manager.db'));
    if (!await mainDbFile.exists()) {
      throw Exception('Active SQLite database file not found at ${mainDbFile.path}');
    }
    mainDbBytes = await mainDbFile.readAsBytes();

    final walFile = File(join(dbPath, 'loan_manager.db-wal'));
    final shmFile = File(join(dbPath, 'loan_manager.db-shm'));
    if (await walFile.exists()) {
      walBytes = await walFile.readAsBytes();
      debugPrint('BackupService: Collected WAL file (${walBytes.length} bytes).');
    }
    if (await shmFile.exists()) {
      shmBytes = await shmFile.readAsBytes();
      debugPrint('BackupService: Collected SHM file (${shmBytes.length} bytes).');
    }
    
    final mainDbHash = calculateSHA256(mainDbBytes);
    
    // 4. Fetch record counts for metadata.json
    final borrowerCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM borrowers WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
    final loanCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM loans WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
    final paymentCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM payments WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
    final expenseCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM expenses WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
    final investmentCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM investments WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
    final serviceCostCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM service_costs WHERE COALESCE(is_deleted, 0) = 0')) ?? 0;
    
    final metadata = {
      'app_version': '1.0.0',
      'schema_version': 12,
      'backup_timestamp': DateTime.now().toUtc().toIso8601String(),
      'borrower_count': borrowerCount,
      'loan_count': loanCount,
      'payment_count': paymentCount,
      'expense_count': expenseCount,
      'investment_count': investmentCount,
      'service_cost_count': serviceCostCount,
      'device_info': '${Platform.operatingSystem} - ${Platform.localHostname}',
      'android_version': Platform.operatingSystemVersion,
      'database_checksum': mainDbHash,
    };
    
    final metadataString = jsonEncode(metadata);
    final metadataBytes = utf8.encode(metadataString);
    
    // 5. Create ZIP Archive
    final archive = Archive();
    archive.addFile(ArchiveFile('credits_app.db', mainDbBytes.length, mainDbBytes));
    if (walBytes != null) {
      archive.addFile(ArchiveFile('credits_app.db-wal', walBytes.length, walBytes));
    }
    if (shmBytes != null) {
      archive.addFile(ArchiveFile('credits_app.db-shm', shmBytes.length, shmBytes));
    }
    archive.addFile(ArchiveFile('metadata.json', metadataBytes.length, metadataBytes));
    
    // Package files into a ZIP archive in-memory
    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw Exception('Failed to encode ZIP archive.');
    }
    
    return zipBytes;
  }

  /// Creates a ZIP archive containing the full SQLite database files and metadata.
  /// Then, encrypts the ZIP file bytes using AES-256-CBC.
  /// Runs encryption inside a background isolate.
  static Future<List<int>> createEncryptedBackup({String? email}) async {
    // 1. Create the full database backup zip bytes
    final zipBytes = await createFullDatabaseBackupBytes();
    
    // 2. Encrypt the ZIP bytes inside a background isolate to prevent UI stutters
    final encryptedBytes = await compute(_encryptTask, _EncryptionIsolateParams(zipBytes, email));
    
    return encryptedBytes;
  }

  // Legacy encrypted zip restore logic has been completely retired in favor of the new single Excel backup restore architecture.
}

