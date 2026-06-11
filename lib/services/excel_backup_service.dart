import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../database/db_helper.dart';
import '../utils/date_parser.dart';

class ExcelBackupService {
  static final _db = DBHelper();

  static Future<void> _requestStoragePermission() async {
    if (!Platform.isAndroid) return;
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      final sdkInt = int.tryParse(result.stdout.toString().trim()) ?? 29;
      final status = sdkInt >= 30
          ? await Permission.manageExternalStorage.request()
          : await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied. Cannot save/read backup file.');
      }
    } catch (_) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        throw Exception('Storage permission denied.');
      }
    }
  }

  // ==========================================
  // EXPORT BACKUP
  // ==========================================
  static Future<String> exportFullBackup({void Function(double progress)? onProgress}) async {
    await _requestStoragePermission();

    final excel = Excel.createExcel();
    final db = await _db.database;
    
    // Fetch all raw data (including soft-deleted)
    final borrowers = await db.rawQuery('SELECT * FROM borrowers');
    final loans = await db.rawQuery('SELECT * FROM loans');
    final payments = await db.rawQuery('SELECT * FROM payments');
    final expenses = await db.rawQuery('SELECT * FROM expenses');
    final investments = await db.rawQuery('SELECT * FROM investments');
    final serviceCosts = await db.rawQuery('SELECT * FROM service_costs');

    final totalRows = borrowers.length +
        loans.length +
        payments.length +
        expenses.length +
        investments.length +
        serviceCosts.length;
    final totalRowsVal = totalRows == 0 ? 1 : totalRows;
    int writtenRows = 0;

    void handleRowWritten() {
      writtenRows++;
      onProgress?.call((writtenRows / totalRowsVal).clamp(0.0, 1.0));
    }

    // Build Summary
    final summarySheet = excel['Summary'];
    excel.setDefaultSheet('Summary');
    
    double totalLoaned = 0, totalCollected = 0, activeLoans = 0, closedLoans = 0;
    double totalExpenses = 0, totalInvestments = 0, outstanding = 0, totalServiceCosts = 0;
    
    for (var l in loans) {
      if ((l['is_deleted'] as int? ?? 0) == 0) {
        if (l['status'] == 'active') activeLoans++;
        if (l['status'] == 'cleared') closedLoans++;
        totalLoaned += (l['loan_amount'] as num).toDouble();
      }
    }
    for (var p in payments) {
      if ((p['is_deleted'] as int? ?? 0) == 0) {
        totalCollected += (p['amount'] as num).toDouble();
      }
    }
    for (var e in expenses) {
      if ((e['is_deleted'] as int? ?? 0) == 0) {
        totalExpenses += (e['amount'] as num).toDouble();
      }
    }
    for (var i in investments) {
      if ((i['is_deleted'] as int? ?? 0) == 0) {
        totalInvestments += (i['amount'] as num).toDouble();
      }
    }
    for (var sc in serviceCosts) {
      if ((sc['is_deleted'] as int? ?? 0) == 0) {
        totalServiceCosts += (sc['amount'] as num).toDouble();
      }
    }
    
    // Total outstanding is calculated dynamically by DB summary
    final activeLoansRes = await db.rawQuery("SELECT SUM(loan_amount + interest_amount) as total FROM loans WHERE status = 'active' AND COALESCE(is_deleted, 0) = 0");
    final activeCollectedRes = await db.rawQuery("SELECT SUM(p.amount) as total FROM payments p JOIN loans l ON p.loan_id = l.id WHERE l.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l.is_deleted, 0) = 0");
    outstanding = ((activeLoansRes.first['total'] as num?)?.toDouble() ?? 0.0) - ((activeCollectedRes.first['total'] as num?)?.toDouble() ?? 0.0);
    
    _addHeader(summarySheet, ['Metric', 'Value']);
    _addRow(summarySheet, ['Total Borrowers', borrowers.where((b) => (b['is_deleted'] as int? ?? 0) == 0).length.toString()]);
    _addRow(summarySheet, ['Active Loans', activeLoans.toString()]);
    _addRow(summarySheet, ['Closed Loans', closedLoans.toString()]);
    _addRow(summarySheet, ['Total Lent Amount', totalLoaned.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Collected Amount', totalCollected.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Outstanding Value', outstanding.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Expenses', totalExpenses.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Service Costs', totalServiceCosts.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Investments', totalInvestments.toStringAsFixed(2)]);
    final onHand = totalInvestments - totalLoaned + totalCollected - totalExpenses + totalServiceCosts;
    _addRow(summarySheet, ['On Hand Cash', onHand.toStringAsFixed(2)]);
    _addRow(summarySheet, ['NET Balance', onHand.toStringAsFixed(2)]);
    summarySheet.appendRow([TextCellValue('')]);
    _addHeader(summarySheet, ['System Info', 'Value']);
    _addRow(summarySheet, ['Export Timestamp', DateTime.now().toIso8601String()]);

    // Build Metadata
    final metaSheet = excel['Metadata'];
    _addHeader(metaSheet, ['Key', 'Value']);
    _addRow(metaSheet, ['schema_version', '12']);
    _addRow(metaSheet, ['backup_id', const Uuid().v4()]);
    _addRow(metaSheet, ['borrowers_count', borrowers.length.toString()]);
    _addRow(metaSheet, ['loans_count', loans.length.toString()]);
    _addRow(metaSheet, ['payments_count', payments.length.toString()]);
    _addRow(metaSheet, ['expenses_count', expenses.length.toString()]);
    _addRow(metaSheet, ['investments_count', investments.length.toString()]);
    _addRow(metaSheet, ['service_costs_count', serviceCosts.length.toString()]);

    // Save configuration settings
    final themePrefs = await SharedPreferences.getInstance();
    final isDark = themePrefs.getBool('theme_mode') ?? false;
    final themeStr = isDark ? 'dark' : 'light';

    const secureStorage = FlutterSecureStorage();
    final pin = await secureStorage.read(key: 'app_lock_pin') ?? '';
    final appLockEnabled = await secureStorage.read(key: 'app_lock_enabled') ?? 'false';
    final biometricEnabled = await secureStorage.read(key: 'app_lock_biometric_enabled') ?? 'false';

    _addRow(metaSheet, ['theme_mode', themeStr]);
    _addRow(metaSheet, ['app_lock_enabled', appLockEnabled]);
    _addRow(metaSheet, ['app_lock_pin', pin]);
    _addRow(metaSheet, ['app_lock_biometric_enabled', biometricEnabled]);

    // Export Tables
    await _exportTable(excel['Borrowers'], borrowers, handleRowWritten);
    await _exportTable(excel['Loans'], loans, handleRowWritten);
    await _exportTable(excel['Payments'], payments, handleRowWritten);
    await _exportTable(excel['Expenses'], expenses, handleRowWritten);
    await _exportTable(excel['Investments'], investments, handleRowWritten);
    
    final serviceCostsExport = serviceCosts.map((sc) {
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
    await _exportTable(excel['SERVICE_COSTS'], serviceCostsExport, handleRowWritten);

    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file.');
    final fileName = 'CreditBackup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

    final dir = await _getSaveDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Future<void> _exportTable(
    Sheet sheet,
    List<Map<String, dynamic>> data,
    void Function() onRowWritten,
  ) async {
    if (data.isEmpty) return;
    final headers = data.first.keys.toList();
    _addHeader(sheet, headers);
    int count = 0;
    for (final row in data) {
      sheet.appendRow(headers.map((h) => TextCellValue(row[h]?.toString() ?? '')).toList());
      onRowWritten();
      count++;
      if (count % 20 == 0) {
        await Future.delayed(Duration.zero);
      }
    }
  }

  static Sheet? _getSheetCaseInsensitive(Excel excel, String name) {
    final nameLower = name.toLowerCase();
    for (final key in excel.tables.keys) {
      if (key.toLowerCase() == nameLower) {
        return excel.tables[key];
      }
    }
    return null;
  }

  // ==========================================
  // IMPORT BACKUP
  // ==========================================
  static Future<Map<String, int>> previewImport(String? filePath, {List<int>? fileBytes}) async {
    final List<int> bytes;
    if (fileBytes != null) {
      bytes = fileBytes;
    } else if (filePath != null) {
      final file = File(filePath);
      bytes = await file.readAsBytes();
    } else {
      throw ArgumentError('Either filePath or fileBytes must be provided.');
    }
    final excel = Excel.decodeBytes(bytes);
    
    if (_getSheetCaseInsensitive(excel, 'Metadata') == null || _getSheetCaseInsensitive(excel, 'Borrowers') == null) {
      throw Exception('Invalid backup file structure.');
    }
    
    int getCount(String table) {
      final sheet = _getSheetCaseInsensitive(excel, table);
      if (sheet == null || sheet.maxRows <= 1) return 0;
      return sheet.maxRows - 1;
    }

    return {
      'borrowers': getCount('Borrowers'),
      'loans': getCount('Loans'),
      'payments': getCount('Payments'),
      'expenses': getCount('Expenses'),
      'investments': getCount('Investments'),
      'service_costs': getCount('SERVICE_COSTS'),
    };
  }

  static String extractCellValue(CellValue? cellVal) {
    if (cellVal == null) return '';
    if (cellVal is TextCellValue) return cellVal.value.toString();
    if (cellVal is IntCellValue) return cellVal.value.toString();
    if (cellVal is DoubleCellValue) return cellVal.value.toString();
    if (cellVal is BoolCellValue) return cellVal.value ? '1' : '0';
    if (cellVal is DateCellValue) {
      return cellVal.asDateTimeLocal().toIso8601String();
    }
    if (cellVal is DateTimeCellValue) {
      return cellVal.asDateTimeLocal().toIso8601String();
    }
    if (cellVal is TimeCellValue) {
      return cellVal.asDuration().toString();
    }
    return cellVal.toString();
  }

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map, List<String> validColumns) {
    final sanitized = <String, dynamic>{};
    for (final col in validColumns) {
      if (map.containsKey(col)) {
        sanitized[col] = map[col];
      }
    }
    return sanitized;
  }

  static Future<void> importBackup(
    String? filePath, {
    List<int>? fileBytes,
    required bool merge,
    void Function(double progress)? onProgress,
  }) async {
    final db = await _db.database;
    final List<int> bytes;
    if (fileBytes != null) {
      bytes = fileBytes;
    } else if (filePath != null) {
      final file = File(filePath);
      bytes = await file.readAsBytes();
    } else {
      throw ArgumentError('Either filePath or fileBytes must be provided.');
    }
    final excel = Excel.decodeBytes(bytes);
    
    // Count total rows across sheets to parse
    int totalRows = 0;
    final sheetsToCount = ['Borrowers', 'Loans', 'Payments', 'Expenses', 'Investments', 'SERVICE_COSTS'];
    for (final name in sheetsToCount) {
      final sheet = _getSheetCaseInsensitive(excel, name);
      if (sheet != null && sheet.maxRows > 1) {
        totalRows += sheet.maxRows - 1;
      }
    }
    if (totalRows == 0) totalRows = 1;
    int processedRows = 0;

    await db.transaction((txn) async {
      if (!merge) {
        // Wipe local DB
        final tables = ['payments', 'loans', 'borrowers', 'expenses', 'investments', 'service_costs'];
        for (final t in tables) {
          await txn.delete(t);
        }
      }

      // 1. Import Borrowers
      final bSheet = _getSheetCaseInsensitive(excel, 'Borrowers');
      Map<String, int> borrowerIdMap = {}; // Maps backup local ID to new local ID
      if (bSheet != null && bSheet.maxRows > 1) {
        final bHeaders = bSheet.rows[0].map((c) => extractCellValue(c?.value)).toList();
        for (int i = 1; i < bSheet.maxRows; i++) {
          final row = bSheet.rows[i];
          final map = _rowToMap(bHeaders, row);
          
          processedRows++;
          onProgress?.call((processedRows / totalRows).clamp(0.0, 1.0));
          if (processedRows % 10 == 0) {
            await Future.delayed(Duration.zero);
          }

          if (map.isEmpty) continue;
          
          final oldId = map['id'].toString();
          
          final sanitized = _sanitizeMap(map, [
            'borrower_code', 'name', 'phone', 'address', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);
          
          // Duplicate detection via borrower_code
          final existing = await txn.query('borrowers', where: 'borrower_code = ?', whereArgs: [sanitized['borrower_code']]);
          if (existing.isNotEmpty) {
            if (merge) {
              final exId = existing.first['id'] as int;
              borrowerIdMap[oldId] = exId;
              await txn.update('borrowers', sanitized, where: 'id = ?', whereArgs: [exId]);
            }
          } else {
            final newId = await txn.insert('borrowers', sanitized);
            borrowerIdMap[oldId] = newId;
          }
        }
      }

      // 2. Import Loans
      final lSheet = _getSheetCaseInsensitive(excel, 'Loans');
      Map<String, int> loanIdMap = {};
      if (lSheet != null && lSheet.maxRows > 1) {
        final lHeaders = lSheet.rows[0].map((c) => extractCellValue(c?.value)).toList();
        for (int i = 1; i < lSheet.maxRows; i++) {
          final row = lSheet.rows[i];
          final map = _rowToMap(lHeaders, row);
          
          processedRows++;
          onProgress?.call((processedRows / totalRows).clamp(0.0, 1.0));
          if (processedRows % 10 == 0) {
            await Future.delayed(Duration.zero);
          }

          if (map.isEmpty) continue;
          
          final oldId = map['id'].toString();
          final oldBorrowerId = map['borrower_id'].toString();
          
          final sanitized = _sanitizeMap(map, [
            'loan_amount', 'interest_amount', 'loan_date',
            'installment_days', 'end_date', 'status', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);
          
          sanitized['borrower_id'] = borrowerIdMap[oldBorrowerId] ?? int.tryParse(oldBorrowerId);
          if (sanitized['borrower_id'] == null) continue; // Orphaned

          if (sanitized['loan_date'] != null) {
            sanitized['loan_date'] = DateParser.safeParse(sanitized['loan_date']).toIso8601String().replaceAll('T', ' ');
          }
          if (sanitized['end_date'] != null) {
            sanitized['end_date'] = DateParser.safeParse(sanitized['end_date']).toIso8601String().replaceAll('T', ' ');
          }

          // Duplicate detection via borrower_id + loan_date + loan_amount
          final existing = await txn.query('loans', 
            where: 'borrower_id = ? AND loan_date = ? AND loan_amount = ?', 
            whereArgs: [sanitized['borrower_id'], sanitized['loan_date'], sanitized['loan_amount']]
          );
          if (existing.isNotEmpty && merge) {
            final exId = existing.first['id'] as int;
            loanIdMap[oldId] = exId;
            await txn.update('loans', sanitized, where: 'id = ?', whereArgs: [exId]);
          } else {
            final newId = await txn.insert('loans', sanitized);
            loanIdMap[oldId] = newId;
          }
        }
      }

      // 3. Import Payments
      final pSheet = _getSheetCaseInsensitive(excel, 'Payments');
      if (pSheet != null && pSheet.maxRows > 1) {
        final pHeaders = pSheet.rows[0].map((c) => extractCellValue(c?.value)).toList();
        for (int i = 1; i < pSheet.maxRows; i++) {
          final row = pSheet.rows[i];
          final map = _rowToMap(pHeaders, row);
          
          processedRows++;
          onProgress?.call((processedRows / totalRows).clamp(0.0, 1.0));
          if (processedRows % 10 == 0) {
            await Future.delayed(Duration.zero);
          }

          if (map.isEmpty) continue;
          
          final oldLoanId = map['loan_id'].toString();
          
          final sanitized = _sanitizeMap(map, [
            'amount', 'payment_date', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);
          
          sanitized['loan_id'] = loanIdMap[oldLoanId] ?? int.tryParse(oldLoanId);
          if (sanitized['loan_id'] == null) continue;

          if (sanitized['payment_date'] != null) {
            sanitized['payment_date'] = DateParser.safeParse(sanitized['payment_date']).toIso8601String().replaceAll('T', ' ');
          }

          // Duplicate detection via loan_id + payment_date + amount
          final existing = await txn.query('payments', 
            where: 'loan_id = ? AND payment_date = ? AND amount = ?', 
            whereArgs: [sanitized['loan_id'], sanitized['payment_date'], sanitized['amount']]
          );
          if (existing.isNotEmpty && merge) {
            await txn.update('payments', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
          } else {
            await txn.insert('payments', sanitized);
          }
        }
      }

      Future<void> importExpenses() async {
        final s = _getSheetCaseInsensitive(excel, 'Expenses');
        if (s != null && s.maxRows > 1) {
          final h = s.rows[0].map((c) => extractCellValue(c?.value)).toList();
          for (int i = 1; i < s.maxRows; i++) {
            final row = s.rows[i];
            final map = _rowToMap(h, row);
            
            processedRows++;
            onProgress?.call((processedRows / totalRows).clamp(0.0, 1.0));
            if (processedRows % 10 == 0) {
              await Future.delayed(Duration.zero);
            }

            if (map.isEmpty) continue;
            
            final sanitized = _sanitizeMap(map, [
              'amount', 'expense_date', 'category', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            ]);

            if (sanitized['expense_date'] != null) {
              sanitized['expense_date'] = DateParser.safeParse(sanitized['expense_date']).toIso8601String().replaceAll('T', ' ');
            }

            final existing = await txn.query('expenses', 
              where: 'created_at = ?', 
              whereArgs: [sanitized['created_at']]
            );
            if (existing.isNotEmpty && merge) {
              await txn.update('expenses', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
            } else {
              await txn.insert('expenses', sanitized);
            }
          }
        }
      }

      Future<void> importInvestments() async {
        final s = _getSheetCaseInsensitive(excel, 'Investments');
        if (s != null && s.maxRows > 1) {
          final h = s.rows[0].map((c) => extractCellValue(c?.value)).toList();
          for (int i = 1; i < s.maxRows; i++) {
            final row = s.rows[i];
            final map = _rowToMap(h, row);
            
            processedRows++;
            onProgress?.call((processedRows / totalRows).clamp(0.0, 1.0));
            if (processedRows % 10 == 0) {
              await Future.delayed(Duration.zero);
            }

            if (map.isEmpty) continue;
            
            final sanitized = _sanitizeMap(map, [
              'amount', 'inv_date', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            ]);

            if (sanitized['inv_date'] != null) {
              sanitized['inv_date'] = DateParser.safeParse(sanitized['inv_date']).toIso8601String().replaceAll('T', ' ');
            }

            final existing = await txn.query('investments', 
              where: 'created_at = ?', 
              whereArgs: [sanitized['created_at']]
            );
            if (existing.isNotEmpty && merge) {
              await txn.update('investments', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
            } else {
              await txn.insert('investments', sanitized);
            }
          }
        }
      }

      Future<void> importServiceCosts() async {
        final s = _getSheetCaseInsensitive(excel, 'SERVICE_COSTS');
        if (s != null && s.maxRows > 1) {
          final h = s.rows[0].map((c) => extractCellValue(c?.value)).toList();
          for (int i = 1; i < s.maxRows; i++) {
            final row = s.rows[i];
            final map = _rowToMap(h, row);
            
            processedRows++;
            onProgress?.call((processedRows / totalRows).clamp(0.0, 1.0));
            if (processedRows % 10 == 0) {
              await Future.delayed(Duration.zero);
            }

            if (map.isEmpty) continue;
            
            final sanitized = _sanitizeMap(map, [
              'amount', 'description', 'dateCreated', 'createdBy', 'timestamp', 'is_deleted'
            ]);

            // Duplicate detection
            final existing = await txn.query('service_costs', 
              where: 'timestamp = ?', 
              whereArgs: [sanitized['timestamp']]
            );
            if (existing.isNotEmpty && merge) {
              await txn.update('service_costs', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
            } else {
              await txn.insert('service_costs', sanitized);
            }
          }
        }
      }

      await importExpenses();
      await importInvestments();
      await importServiceCosts();
    });

    // Run integrity validation
    await _db.validateDataIntegrity();

    // 4. Restore configuration settings from Metadata sheet if available
    try {
      final metaSheet = _getSheetCaseInsensitive(excel, 'Metadata');
      if (metaSheet != null && metaSheet.maxRows > 1) {
        final metadataMap = <String, String>{};
        for (int i = 1; i < metaSheet.maxRows; i++) {
          final row = metaSheet.rows[i];
          if (row.length >= 2) {
            final key = extractCellValue(row[0]?.value);
            final val = extractCellValue(row[1]?.value);
            if (key.isNotEmpty) {
              metadataMap[key] = val;
            }
          }
        }

        // Restore Theme
        final theme = metadataMap['theme_mode'];
        if (theme != null && theme.isNotEmpty) {
          final themePrefs = await SharedPreferences.getInstance();
          await themePrefs.setBool('theme_mode', theme == 'dark');
        }

        // Restore App Lock Settings
        final lockEnabled = metadataMap['app_lock_enabled'];
        final pin = metadataMap['app_lock_pin'];
        final bioEnabled = metadataMap['app_lock_biometric_enabled'];

        const secureStorage = FlutterSecureStorage();
        if (lockEnabled == 'true' && pin != null && pin.isNotEmpty) {
          await secureStorage.write(key: 'app_lock_enabled', value: 'true');
          await secureStorage.write(key: 'app_lock_pin', value: pin);
          await secureStorage.write(key: 'app_lock_biometric_enabled', value: bioEnabled == 'true' ? 'true' : 'false');
        } else if (lockEnabled == 'false') {
          await secureStorage.delete(key: 'app_lock_enabled');
          await secureStorage.delete(key: 'app_lock_pin');
          await secureStorage.delete(key: 'app_lock_biometric_enabled');
        }
        debugPrint('[Restore] Settings restored successfully from backup Metadata.');
      }
    } catch (restoreSettingsError) {
      debugPrint('[Restore] Warning: Failed to restore app settings from Metadata sheet: $restoreSettingsError');
    }
  }

  static Map<String, dynamic> _rowToMap(List<String> headers, List<Data?> row) {
    if (row.every((c) => c == null || c.value == null || extractCellValue(c.value).trim().isEmpty)) {
      return {};
    }
    Map<String, dynamic> map = {};
    for (int i = 0; i < headers.length; i++) {
      if (i < row.length && row[i] != null && row[i]!.value != null) {
        final cellVal = row[i]!.value;
        final val = extractCellValue(cellVal);
        
        if (['id', 'borrower_id', 'loan_id', 'installment_days', 'updated_at', 'created_at', 'is_synced', 'is_deleted', 'timestamp'].contains(headers[i])) {
          map[headers[i]] = int.tryParse(val) ?? 0;
        } else if (['loan_amount', 'interest_amount', 'amount'].contains(headers[i])) {
          map[headers[i]] = double.tryParse(val) ?? 0.0;
        } else {
          map[headers[i]] = val;
        }
      }
    }
    return map;
  }

  static void _addHeader(Sheet sheet, List<String> headers) {
    sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());
  }

  static void _addRow(Sheet sheet, List<String> values) {
    sheet.appendRow(values.map((v) => TextCellValue(v)).toList());
  }

  static Future<Directory> _getSaveDirectory() async {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Download/LoanReports');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }
}

