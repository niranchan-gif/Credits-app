import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../database/db_helper.dart';
import 'google_drive_service.dart';
import 'backup_service.dart';
import 'backup_freshness_service.dart';

class _ExcelGenerationParams {
  final List<Map<String, dynamic>> borrowers;
  final List<Map<String, dynamic>> loans;
  final List<Map<String, dynamic>> payments;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> investments;
  final List<Map<String, dynamic>> serviceCosts;
  final double outstanding;
  final Map<String, String> settings;

  _ExcelGenerationParams({
    required this.borrowers,
    required this.loans,
    required this.payments,
    required this.expenses,
    required this.investments,
    required this.serviceCosts,
    required this.outstanding,
    required this.settings,
  });
}

class GoogleDriveExcelBackupService {
  static final GoogleDriveExcelBackupService _instance = GoogleDriveExcelBackupService._internal();
  factory GoogleDriveExcelBackupService() => _instance;
  GoogleDriveExcelBackupService._internal();

  static DateTime? _lastBackupTime;
  static String? _lastChecksum;
  static bool _isBackupRunning = false;
  static int? _lastBackupDurationMs;

  static Timer? _backupDebounce;

  /// Returns whether a backup is currently running
  bool get isBackupRunning => _isBackupRunning;

  /// Returns last successful backup time
  DateTime? get lastBackupTime => _lastBackupTime;

  /// Returns last backup checksum
  String? get lastChecksum => _lastChecksum;

  /// Returns last backup duration in milliseconds
  int? get lastBackupDurationMs => _lastBackupDurationMs;

  /// Smart backup debounce system scheduling
  static void scheduleBackup() {
    _backupDebounce?.cancel();
    _backupDebounce = Timer(
      const Duration(seconds: 3),
      () async {
        try {
          await GoogleDriveExcelBackupService().performBackup();
        } catch (e) {
          debugPrint('GoogleDriveExcelBackupService: Debounced backup execution failed: $e');
        }
      },
    );
  }

  /// Check Google Drive for credits_backup.xlsx and sync/create on startup
  Future<void> initializeOnStartup() async {
    try {
      final connected = await GoogleDriveService().isConnected();
      if (!connected) {
        debugPrint('GoogleDriveExcelBackupService: Google Drive is not connected. Skipping startup initialization.');
        return;
      }
      
      final authClient = await GoogleDriveService().getAuthClient();
      final driveApi = drive.DriveApi(authClient);
      final folderId = await GoogleDriveService().findOrCreateBackupsFolder(driveApi);
      
      final prefs = await SharedPreferences.getInstance();
      final storedFileId = prefs.getString('google_drive_excel_backup_file_id');
      
      if (storedFileId != null) {
        // We already have a stored file ID, verify it exists on Google Drive
        try {
          final file = await driveApi.files.get(storedFileId) as drive.File;
          if (file.trashed == true) {
            debugPrint('GoogleDriveExcelBackupService: Stored file ID is trashed. Performing search...');
            await _searchAndSyncBackupFile(driveApi, folderId, prefs);
          } else {
            debugPrint('GoogleDriveExcelBackupService: Verified existing stored fileId: $storedFileId');
          }
        } catch (e) {
          debugPrint('GoogleDriveExcelBackupService: Stored file ID not found or invalid: $e. Searching Google Drive...');
          await _searchAndSyncBackupFile(driveApi, folderId, prefs);
        }
      } else {
        // No stored file ID, search Google Drive for the file name
        await _searchAndSyncBackupFile(driveApi, folderId, prefs);
      }
    } catch (e, stack) {
      debugPrint('GoogleDriveExcelBackupService Error during startup init: $e\n$stack');
    }
  }

  Future<void> _searchAndSyncBackupFile(
    drive.DriveApi driveApi,
    String folderId,
    SharedPreferences prefs,
  ) async {
    final storedFileId = prefs.getString('google_drive_excel_backup_file_id');
    bool found = false;
    
    if (storedFileId != null && storedFileId.isNotEmpty) {
      debugPrint('GoogleDriveExcelBackupService: Direct lookup using stored file ID: $storedFileId');
      try {
        final fetchedFile = await driveApi.files.get(
          storedFileId,
          $fields: 'id, name, parents, trashed',
        ) as drive.File;
        if (fetchedFile.parents != null && fetchedFile.parents!.contains(folderId) && fetchedFile.trashed != true) {
          found = true;
          debugPrint('GoogleDriveExcelBackupService: Direct lookup success. Filename: ${fetchedFile.name}');
        }
      } catch (e) {
        debugPrint('GoogleDriveExcelBackupService: Direct lookup failed: $e');
      }
    }
    
    if (!found) {
      debugPrint('GoogleDriveExcelBackupService: Searching Google Drive for credits_backup.xlsx...');
      final listResult = await driveApi.files.list(
        q: "name = 'credits_backup.xlsx' and '$folderId' in parents and trashed = false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      
      final files = listResult.files;
      if (files != null && files.isNotEmpty) {
        final fileId = files.first.id!;
        await prefs.setString('google_drive_excel_backup_file_id', fileId);
        debugPrint('GoogleDriveExcelBackupService: Found existing credits_backup.xlsx on Drive via search. Stored ID: $fileId');
        found = true;
      }
    }
    
    if (!found) {
      debugPrint('GoogleDriveExcelBackupService: credits_backup.xlsx not found on Drive. Clearing stale metadata.');
      await prefs.remove('google_drive_excel_backup_file_id');
      await prefs.remove('google_drive_excel_backup_file_name');
      await prefs.remove('google_drive_excel_backup_timestamp');
      await prefs.remove('google_drive_excel_backup_metadata_json');
      await prefs.remove('last_gdrive_backup_date');
      await prefs.remove('last_gdrive_backup_size');
      await prefs.remove('last_gdrive_backup_health');
      await prefs.remove('last_successful_backup_checksum');
    }
  }

  /// Calculates a deterministic checksum based on all SQLite records.
  Future<String> _calculateSQLiteChecksum() async {
    final db = await DBHelper().database;
    final borrowers = await db.rawQuery('SELECT * FROM borrowers ORDER BY id ASC');
    final loans = await db.rawQuery('SELECT * FROM loans ORDER BY id ASC');
    final payments = await db.rawQuery('SELECT * FROM payments ORDER BY id ASC');
    final expenses = await db.rawQuery('SELECT * FROM expenses ORDER BY id ASC');
    final investments = await db.rawQuery('SELECT * FROM investments ORDER BY id ASC');
    final serviceCosts = await db.rawQuery('SELECT * FROM service_costs ORDER BY id ASC');

    final buffer = StringBuffer();
    buffer.write(jsonEncode(borrowers));
    buffer.write(jsonEncode(loans));
    buffer.write(jsonEncode(payments));
    buffer.write(jsonEncode(expenses));
    buffer.write(jsonEncode(investments));
    buffer.write(jsonEncode(serviceCosts));

    return BackupService.calculateSHA256(utf8.encode(buffer.toString()));
  }

  /// Performs the Excel backup and uploads/updates the SINGLE persistent Excel file in Google Drive.
  Future<void> performBackup({bool force = false, void Function(double progress)? onProgress}) async {
    if (await BackupFreshnessService().areBackupsBlocked()) {
      debugPrint('GoogleDriveExcelBackupService: Backup blocked.');
      return;
    }
    if (_isBackupRunning) {
      debugPrint('GoogleDriveExcelBackupService: Backup already in progress. Skipping.');
      return;
    }
    
    _isBackupRunning = true;
    final stopwatch = Stopwatch()..start();
    debugPrint('[Backup] Started');
    
    File? tempFile;
    try {
      final connected = await GoogleDriveService().isConnected();
      if (!connected) {
        debugPrint('GoogleDriveExcelBackupService: Google Drive is not connected. Skipping backup.');
        return;
      }
      
      // Calculate Checksum of SQLite data
      debugPrint('[Backup] Reading SQLite data...');
      debugPrint('[Backup] Calculating checksum...');
      final checksum = await _calculateSQLiteChecksum();
      
      final prefs = await SharedPreferences.getInstance();
      final lastSuccessfulChecksum = prefs.getString('last_successful_backup_checksum');
      
      if (checksum == lastSuccessfulChecksum && !force) {
        debugPrint('[Backup] No changes detected');
        debugPrint('Backup skipped: No data changes detected');
        _lastBackupTime = DateTime.now();
        _lastChecksum = checksum;
        _lastBackupDurationMs = stopwatch.elapsedMilliseconds;
        debugPrint('[Backup] Finished in $_lastBackupDurationMs ms');
        return;
      }
      
      // If we got here, either there are changes or we forced it.
      debugPrint('[Backup] Generating Excel workbook...');
      
      // Retrieve SQLite data to pass to background isolate
      final db = await DBHelper().database;
      final borrowers = await db.rawQuery('SELECT * FROM borrowers');
      final loans = await db.rawQuery('SELECT * FROM loans');
      final payments = await db.rawQuery('SELECT * FROM payments');
      final expenses = await db.rawQuery('SELECT * FROM expenses');
      final investments = await db.rawQuery('SELECT * FROM investments');
      final serviceCosts = await db.rawQuery('SELECT * FROM service_costs');
      
      // Calculate outstanding value
      final activeLoansRes = await db.rawQuery("SELECT SUM(loan_amount + interest_amount) as total FROM loans WHERE status = 'active' AND COALESCE(is_deleted, 0) = 0");
      final activeCollectedRes = await db.rawQuery("SELECT SUM(p.amount) as total FROM payments p JOIN loans l ON p.loan_id = l.id WHERE l.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l.is_deleted, 0) = 0");
      final outstanding = ((activeLoansRes.first['total'] as num?)?.toDouble() ?? 0.0) - ((activeCollectedRes.first['total'] as num?)?.toDouble() ?? 0.0);
      
      // Read current app configurations/settings to save in backup
      final themePrefs = await SharedPreferences.getInstance();
      final isDark = themePrefs.getBool('theme_mode') ?? false;
      final themeStr = isDark ? 'dark' : 'light';
  
      const secureStorage = FlutterSecureStorage();
      final pin = await secureStorage.read(key: 'app_lock_pin') ?? '';
      final appLockEnabled = await secureStorage.read(key: 'app_lock_enabled') ?? 'false';
      final biometricEnabled = await secureStorage.read(key: 'app_lock_biometric_enabled') ?? 'false';
  
      final settings = {
        'theme_mode': themeStr,
        'app_lock_enabled': appLockEnabled,
        'app_lock_pin': pin,
        'app_lock_biometric_enabled': biometricEnabled,
      };
  
      // Build parameters for isolate
      final params = _ExcelGenerationParams(
        borrowers: borrowers,
        loans: loans,
        payments: payments,
        expenses: expenses,
        investments: investments,
        serviceCosts: serviceCosts,
        outstanding: outstanding,
        settings: settings,
      );
      
      // Run generation on background thread/isolate!
      final excelBytes = await compute(_buildExcelBytes, params);
      
      // Validate workbook before upload
      debugPrint('[Backup] Running workbook validation...');
      final isValid = await _validateWorkbookBytes(excelBytes);
      if (!isValid) {
        throw Exception('Generated Excel workbook failed backup health validation!');
      }
 
      // Write generated bytes to temp file on mobile/desktop
      final tempDir = await getTemporaryDirectory();
      tempFile = File('${tempDir.path}/credits_backup_temp.xlsx');
      await tempFile.writeAsBytes(excelBytes, flush: true);
      
      final authClient = await GoogleDriveService().getAuthClient();
      final driveApi = drive.DriveApi(authClient);
      final folderId = await GoogleDriveService().findOrCreateBackupsFolder(driveApi);
      final existingFileId = prefs.getString('google_drive_excel_backup_file_id');
      
      final driveFile = drive.File()
        ..name = 'credits_backup.xlsx'
        ..mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      
      final trackedStream = GoogleDriveService.trackStreamProgress(
        tempFile.openRead(),
        excelBytes.length,
        onProgress,
      );
      final media = drive.Media(
        trackedStream,
        excelBytes.length,
        contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      
      debugPrint('[Backup] Uploading to Google Drive...');
      String activeFileId = '';
      
      if (existingFileId == null) {
        driveFile.parents = [folderId];
        final createdFile = await driveApi.files.create(
          driveFile,
          uploadMedia: media,
        );
        activeFileId = createdFile.id!;
        await prefs.setString('google_drive_excel_backup_file_id', activeFileId);
      } else {
        debugPrint('[Backup] Updating existing Drive file...');
        try {
          final updatedFile = await driveApi.files.update(
            driveFile,
            existingFileId,
            uploadMedia: media,
          );
          activeFileId = updatedFile.id!;
        } catch (e) {
          debugPrint('GoogleDriveExcelBackupService: Update failed ($e). Recreating file...');
          await prefs.remove('google_drive_excel_backup_file_id');
          final trackedStreamFallback = GoogleDriveService.trackStreamProgress(
            tempFile.openRead(),
            excelBytes.length,
            onProgress,
          );
          final mediaFallback = drive.Media(
            trackedStreamFallback,
            excelBytes.length,
            contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          driveFile.parents = [folderId];
          final createdFile = await driveApi.files.create(
            driveFile,
            uploadMedia: mediaFallback,
          );
          activeFileId = createdFile.id!;
          await prefs.setString('google_drive_excel_backup_file_id', activeFileId);
        }
      }
      
      debugPrint('[Backup] Upload complete. Uploaded file name: ${driveFile.name}, ID: $activeFileId, Folder ID: $folderId');
 
      // Validate file existence immediately after backup upload
      debugPrint('[Backup] Validating uploaded file existence on Google Drive...');
      try {
        final verifiedFile = await driveApi.files.get(
          activeFileId,
          $fields: 'id, name, size, modifiedTime, createdTime',
        ) as drive.File;
        debugPrint('[Backup] Upload validation successful. Verified File ID: ${verifiedFile.id}, Name: ${verifiedFile.name}, Size: ${verifiedFile.size}');
        
        final driveTime = verifiedFile.modifiedTime ?? verifiedFile.createdTime;
        if (driveTime != null) {
          await prefs.setString('local_db_last_modified_timestamp', driveTime.toUtc().toIso8601String());
          debugPrint('[Backup] Updated local database modification timestamp to match Drive: ${driveTime.toUtc().toIso8601String()}');
        }
      } catch (validationError) {
        debugPrint('[Backup] ERROR: Uploaded file verification failed! Error: $validationError');
        throw Exception('Uploaded file validation failed: $validationError');
      }
 
      final nowStr = DateTime.now().toUtc().toIso8601String();
      await prefs.setString('google_drive_excel_backup_file_id', activeFileId);
      await prefs.setString('google_drive_excel_backup_file_name', 'credits_backup.xlsx');
      await prefs.setString('google_drive_excel_backup_timestamp', nowStr);
 
      final driveBackupMetadata = {
        'fileId': activeFileId,
        'fileName': 'credits_backup.xlsx',
        'timestamp': nowStr,
      };
      await prefs.setString('google_drive_excel_backup_metadata_json', jsonEncode(driveBackupMetadata));
      debugPrint('[Backup] Stored file ID, filename, and timestamp successfully.');
      
      // Calculate record counts for metadata
      final bCount = borrowers.where((b) => (b['is_deleted'] as int? ?? 0) == 0).length;
      final lCount = loans.where((l) => (l['is_deleted'] as int? ?? 0) == 0).length;
      final pCount = payments.where((p) => (p['is_deleted'] as int? ?? 0) == 0).length;
      final eCount = expenses.where((e) => (e['is_deleted'] as int? ?? 0) == 0).length;
      final iCount = investments.where((i) => (i['is_deleted'] as int? ?? 0) == 0).length;
      final scCount = serviceCosts.where((sc) => (sc['is_deleted'] as int? ?? 0) == 0).length;
      final recordCount = bCount + lCount + pCount + eCount + iCount + scCount;
      
      // Save last successful checksum
      await prefs.setString('last_successful_backup_checksum', checksum);
      
      // Update local metadata JSON (Version 2)
      _lastBackupDurationMs = stopwatch.elapsedMilliseconds;
      await _updateLocalMetadata(
        recordCount: recordCount,
        checksum: checksum,
        lastBackupDurationMs: _lastBackupDurationMs!,
        backupStatus: 'success',
        driveFileId: activeFileId,
      );
      
      _lastBackupTime = DateTime.now();
      _lastChecksum = checksum;
      
      debugPrint('[Backup] Finished in $_lastBackupDurationMs ms');
    } catch (e, stack) {
      debugPrint('GoogleDriveExcelBackupService error during performBackup: $e\n$stack');
      rethrow;
    } finally {
      _isBackupRunning = false;
      
      // Clean up temp file
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          debugPrint('[Backup] Temp file deleted');
        } catch (cleanupError) {
          debugPrint('GoogleDriveExcelBackupService: Failed to delete temporary file: $cleanupError');
        }
      }
    }
  }

  // Build workbook generation methods deleted/preserved in isolate
  static List<int> _buildExcelBytes(_ExcelGenerationParams params) {
    final excel = Excel.createExcel();
    final summarySheet = excel['Summary'];
    excel.setDefaultSheet('Summary');
    
    double totalLoaned = 0, totalCollected = 0, activeLoans = 0, closedLoans = 0;
    double totalExpenses = 0, totalInvestments = 0, totalServiceCosts = 0;
    
    for (var l in params.loans) {
      if ((l['is_deleted'] as int? ?? 0) == 0) {
        if (l['status'] == 'active') activeLoans++;
        if (l['status'] == 'cleared') closedLoans++;
        totalLoaned += (l['loan_amount'] as num).toDouble();
      }
    }
    for (var p in params.payments) {
      if ((p['is_deleted'] as int? ?? 0) == 0) {
        totalCollected += (p['amount'] as num).toDouble();
      }
    }
    for (var e in params.expenses) {
      if ((e['is_deleted'] as int? ?? 0) == 0) {
        totalExpenses += (e['amount'] as num).toDouble();
      }
    }
    for (var i in params.investments) {
      if ((i['is_deleted'] as int? ?? 0) == 0) {
        totalInvestments += (i['amount'] as num).toDouble();
      }
    }
    for (var sc in params.serviceCosts) {
      if ((sc['is_deleted'] as int? ?? 0) == 0) {
        totalServiceCosts += (sc['amount'] as num).toDouble();
      }
    }
    
    _addHeaderStatic(summarySheet, ['Metric', 'Value']);
    _addRowStatic(summarySheet, ['Total Borrowers', params.borrowers.where((b) => (b['is_deleted'] as int? ?? 0) == 0).length.toString()]);
    _addRowStatic(summarySheet, ['Active Loans', activeLoans.toString()]);
    _addRowStatic(summarySheet, ['Closed Loans', closedLoans.toString()]);
    _addRowStatic(summarySheet, ['Total Lent Amount', totalLoaned.toStringAsFixed(2)]);
    _addRowStatic(summarySheet, ['Total Collected Amount', totalCollected.toStringAsFixed(2)]);
    _addRowStatic(summarySheet, ['Total Outstanding Value', params.outstanding.toStringAsFixed(2)]);
    _addRowStatic(summarySheet, ['Total Expenses', totalExpenses.toStringAsFixed(2)]);
    _addRowStatic(summarySheet, ['Total Service Costs', totalServiceCosts.toStringAsFixed(2)]);
    _addRowStatic(summarySheet, ['Total Investments', totalInvestments.toStringAsFixed(2)]);
    final onHand = totalInvestments - totalLoaned + totalCollected - totalExpenses + totalServiceCosts;
    _addRowStatic(summarySheet, ['On Hand Cash', onHand.toStringAsFixed(2)]);
    _addRowStatic(summarySheet, ['NET Balance', onHand.toStringAsFixed(2)]);
    summarySheet.appendRow([TextCellValue('')]);
    _addHeaderStatic(summarySheet, ['System Info', 'Value']);
    _addRowStatic(summarySheet, ['Export Timestamp', DateTime.now().toIso8601String()]);

    // Build Metadata Sheet
    final metaSheet = excel['Metadata'];
    _addHeaderStatic(metaSheet, ['Key', 'Value']);
    _addRowStatic(metaSheet, ['schema_version', '12']);
    _addRowStatic(metaSheet, ['borrowers_count', params.borrowers.length.toString()]);
    _addRowStatic(metaSheet, ['loans_count', params.loans.length.toString()]);
    _addRowStatic(metaSheet, ['payments_count', params.payments.length.toString()]);
    _addRowStatic(metaSheet, ['expenses_count', params.expenses.length.toString()]);
    _addRowStatic(metaSheet, ['investments_count', params.investments.length.toString()]);
    _addRowStatic(metaSheet, ['service_costs_count', params.serviceCosts.length.toString()]);

    // Save configuration settings
    _addRowStatic(metaSheet, ['theme_mode', params.settings['theme_mode'] ?? 'light']);
    _addRowStatic(metaSheet, ['app_lock_enabled', params.settings['app_lock_enabled'] ?? 'false']);
    _addRowStatic(metaSheet, ['app_lock_pin', params.settings['app_lock_pin'] ?? '']);
    _addRowStatic(metaSheet, ['app_lock_biometric_enabled', params.settings['app_lock_biometric_enabled'] ?? 'false']);

    // Export Tables
    _exportTableStatic(excel['Borrowers'], params.borrowers);
    _exportTableStatic(excel['Loans'], params.loans);
    _exportTableStatic(excel['Payments'], params.payments);
    _exportTableStatic(excel['Expenses'], params.expenses);
    _exportTableStatic(excel['Investments'], params.investments);
    
    final serviceCostsExport = params.serviceCosts.map((sc) {
      return {
        'id': sc['id'],
        'amount': sc['amount'],
        'description': sc['description'],
        'dateCreated': sc['dateCreated'],
        'createdBy': sc['createdBy'],
        'timestamp': sc['timestamp'],
        'is_deleted': sc['is_deleted'],
      };
    }).toList();
    _exportTableStatic(excel['SERVICE_COSTS'], serviceCostsExport);

    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Failed to encode Excel file inside isolate.');
    }
    return bytes;
  }

  static void _exportTableStatic(Sheet sheet, List<Map<String, dynamic>> data) {
    if (data.isEmpty) return;
    final headers = data.first.keys.toList();
    _addHeaderStatic(sheet, headers);
    for (final row in data) {
      // Null row filtering
      final isAllNull = row.values.every((v) => v == null || v.toString().trim().isEmpty);
      if (isAllNull) continue;

      // Invalid data sanitization
      final cells = headers.map((h) {
        final val = row[h];
        if (val == null) return TextCellValue('');
        String str = val.toString();
        // Sanitize string to remove control characters
        str = str.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
        return TextCellValue(str);
      }).toList();
      sheet.appendRow(cells);
    }
  }

  static void _addHeaderStatic(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  }

  static void _addRowStatic(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }

  /// Validate the excel workbook bytes structure by attempting to decode it.
  Future<bool> _validateWorkbookBytes(List<int> bytes) async {
    try {
      if (bytes.isEmpty) {
        debugPrint('GoogleDriveExcelBackupService: Validation failed, bytes are empty.');
        return false;
      }
      final excel = Excel.decodeBytes(bytes);
      
      // Empty sheet detection & corrupted workbook check
      if (excel.tables.isEmpty) {
        debugPrint('GoogleDriveExcelBackupService: Validation failed, Excel tables are empty.');
        return false;
      }
      final requiredSheets = ['Summary', 'Metadata', 'Borrowers', 'Loans', 'Payments', 'Expenses', 'Investments', 'SERVICE_COSTS'];
      for (final sheetName in requiredSheets) {
        if (!excel.tables.containsKey(sheetName)) {
          debugPrint('GoogleDriveExcelBackupService: Validation failed, missing sheet "$sheetName".');
          return false;
        }
      }
      debugPrint('GoogleDriveExcelBackupService: Excel validation passed. Tables: ${excel.tables.keys.join(', ')}');
      return true;
    } catch (e) {
      debugPrint('GoogleDriveExcelBackupService: Workbook bytes validation failed with error: $e');
      return false;
    }
  }

  Future<File> _getMetadataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/backup_metadata.json');
  }

  /// Create and update backup_metadata.json locally (Version 2).
  Future<void> _updateLocalMetadata({
    required int recordCount,
    required String checksum,
    required int lastBackupDurationMs,
    required String backupStatus,
    required String driveFileId,
  }) async {
    final metadata = {
      'version': 2,
      'lastBackup': DateTime.now().toUtc().toIso8601String(),
      'recordCount': recordCount,
      'checksum': checksum,
      'lastBackupDurationMs': lastBackupDurationMs,
      'backupStatus': backupStatus,
      'driveFileId': driveFileId,
      'fileName': 'credits_backup.xlsx',
    };



    try {
      final file = await _getMetadataFile();
      await file.writeAsString(jsonEncode(metadata), flush: true);
      debugPrint('[Backup] Metadata updated');
    } catch (e) {
      debugPrint('GoogleDriveExcelBackupService: Failed to save local metadata file: $e');
    }
  }
}

