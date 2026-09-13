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

  static int _parseEpoch(dynamic val) {
    if (val == null) return DateTime.now().millisecondsSinceEpoch;
    if (val is int) return val;
    final str = val.toString().trim();
    if (str.isEmpty || str == '-') return DateTime.now().millisecondsSinceEpoch;
    final numVal = int.tryParse(str);
    if (numVal != null) return numVal;
    final d = DateParser.safeParse(str);
    return d.millisecondsSinceEpoch;
  }

  static String _formatEpochDate(dynamic val) {
    final ms = _parseEpoch(val);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  static String _formatDateOnly(dynamic val) {
    if (val == null || val.toString().trim().isEmpty || val.toString().trim() == '-') return '-';
    final d = DateParser.safeParse(val);
    return DateFormat('yyyy-MM-dd').format(d);
  }

  static String _formatDateTime(dynamic val) {
    if (val == null || val.toString().trim().isEmpty || val.toString().trim() == '-') return '-';
    final d = DateParser.safeParse(val);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(d);
  }

  // ==========================================
  // EXPORT FULL BACKUP & READABLE MASTER REPORT
  // ==========================================
  static Future<String> exportFullBackup({void Function(double progress)? onProgress}) async {
    await _requestStoragePermission();

    final excel = Excel.createExcel();
    final db = await _db.database;

    // Fetch all raw data (including soft-deleted for backup fidelity)
    final borrowers = await db.rawQuery('SELECT * FROM borrowers ORDER BY CAST(borrower_code AS INTEGER) ASC, id ASC');
    final loans = await db.rawQuery('SELECT * FROM loans ORDER BY loan_date ASC, id ASC');
    final payments = await db.rawQuery('SELECT * FROM payments ORDER BY payment_date ASC, id ASC');
    final expenses = await db.rawQuery('SELECT * FROM expenses ORDER BY expense_date ASC, id ASC');
    final investments = await db.rawQuery('SELECT * FROM investments ORDER BY inv_date ASC, id ASC');
    final serviceCosts = await db.rawQuery('SELECT * FROM service_costs ORDER BY dateCreated ASC, id ASC');

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

    // Lookup caches
    final borrowerMap = <int, Map<String, dynamic>>{
      for (final b in borrowers) (b['id'] as int): b,
    };
    final loanMap = <int, Map<String, dynamic>>{
      for (final l in loans) (l['id'] as int): l,
    };

    // Calculate aggregated metrics for Summary
    double totalLoaned = 0, totalCollected = 0, activeLoans = 0, closedLoans = 0;
    double totalExpenses = 0, totalInvestments = 0, outstanding = 0, totalServiceCosts = 0;
    double activePrincipal = 0, activeInterest = 0, activeTotalDue = 0, activeCollected = 0;

    for (var l in loans) {
      if ((l['is_deleted'] as int? ?? 0) == 0) {
        final principal = (l['loan_amount'] as num).toDouble();
        final interest = (l['interest_amount'] as num).toDouble();
        totalLoaned += principal;
        if (l['status'] == 'active') {
          activeLoans++;
          activePrincipal += principal;
          activeInterest += interest;
          activeTotalDue += (principal + interest);
        } else {
          closedLoans++;
        }
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

    final activeCollectedRes = await db.rawQuery(
        "SELECT SUM(p.amount) as total FROM payments p JOIN loans l ON p.loan_id = l.id WHERE l.status = 'active' AND COALESCE(p.is_deleted, 0) = 0 AND COALESCE(l.is_deleted, 0) = 0");
    activeCollected = (activeCollectedRes.first['total'] as num?)?.toDouble() ?? 0.0;
    outstanding = (activeTotalDue - activeCollected).clamp(0.0, double.infinity);
    final onHand = totalInvestments - totalLoaned + totalCollected - totalExpenses + totalServiceCosts;

    // Active & Closed borrowers count
    int activeBorrowersCount = 0;
    int closedBorrowersCount = 0;
    for (var b in borrowers) {
      if ((b['is_deleted'] as int? ?? 0) == 0) {
        final bId = b['id'] as int;
        final hasActive = loans.any((l) => l['borrower_id'] == bId && l['status'] == 'active' && (l['is_deleted'] as int? ?? 0) == 0);
        if (hasActive) {
          activeBorrowersCount++;
        } else {
          closedBorrowersCount++;
        }
      }
    }

    // ── SHEET 1: Overall Summary (Executive Master Dashboard) ───
    final summarySheet = excel['Overall Summary'];
    excel.setDefaultSheet('Overall Summary');

    _addHeader(summarySheet, ['Credits', '']);
    _addRow(summarySheet, ['Report', 'Overall Summary & Local Backup']);
    _addRow(summarySheet, ['Report Generated On', DateFormat('dd MMM yyyy, hh:mm:ss a').format(DateTime.now())]);
    _addRow(summarySheet, ['Backup Schema Version', '12']);
    summarySheet.appendRow([TextCellValue('')]);

    _addHeader(summarySheet, ['Overall Summary', 'Amount (₹)']);
    _addRow(summarySheet, ['On Hand Cash', onHand.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Invested', totalInvestments.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Loaned Ever', totalLoaned.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Collected Ever', totalCollected.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Expenses', totalExpenses.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Total Service Costs', totalServiceCosts.toStringAsFixed(2)]);
    _addRow(summarySheet, ['To Recover', activeTotalDue.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Collected', activeCollected.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Pending', outstanding.toStringAsFixed(2)]);
    summarySheet.appendRow([TextCellValue('')]);

    _addHeader(summarySheet, ['Loan Portfolio', 'Value']);
    _addRow(summarySheet, ['Borrowers', borrowers.length.toString()]);
    _addRow(summarySheet, ['Active Borrowers', activeBorrowersCount.toString()]);
    _addRow(summarySheet, ['Closed Borrowers', closedBorrowersCount.toString()]);
    _addRow(summarySheet, ['Total Loans Ever', loans.length.toString()]);
    _addRow(summarySheet, ['Active Loans', activeLoans.toInt().toString()]);
    _addRow(summarySheet, ['Closed Loans', closedLoans.toInt().toString()]);
    _addRow(summarySheet, ['Active Principal', activePrincipal.toStringAsFixed(2)]);
    _addRow(summarySheet, ['Active Interest', activeInterest.toStringAsFixed(2)]);
    summarySheet.appendRow([TextCellValue('')]);

    _addHeader(summarySheet, ['Database Records Breakdown', 'Record Count']);
    _addRow(summarySheet, ['Borrowers Count', borrowers.length.toString()]);
    _addRow(summarySheet, ['Loans Count', loans.length.toString()]);
    _addRow(summarySheet, ['Payments Count', payments.length.toString()]);
    _addRow(summarySheet, ['Expenses Count', expenses.length.toString()]);
    _addRow(summarySheet, ['Investments Count', investments.length.toString()]);
    _addRow(summarySheet, ['Service Costs Count', serviceCosts.length.toString()]);

    // ── SHEET 2: Metadata (for settings and app verification) ─────
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

    final themePrefs = await SharedPreferences.getInstance();
    final isDark = themePrefs.getBool('theme_mode') ?? false;
    const secureStorage = FlutterSecureStorage();
    String pin = '';
    String appLockEnabled = 'false';
    String biometricEnabled = 'false';
    try {
      pin = await secureStorage.read(key: 'app_lock_pin') ?? '';
      appLockEnabled = await secureStorage.read(key: 'app_lock_enabled') ?? 'false';
      biometricEnabled = await secureStorage.read(key: 'app_lock_biometric_enabled') ?? 'false';
    } catch (e) {
      debugPrint('[Export] Warning: Failed to read secure storage: $e');
    }

    _addRow(metaSheet, ['theme_mode', isDark ? 'dark' : 'light']);
    _addRow(metaSheet, ['app_lock_enabled', appLockEnabled]);
    _addRow(metaSheet, ['app_lock_pin', pin]);
    _addRow(metaSheet, ['app_lock_biometric_enabled', biometricEnabled]);

    // ── SHEET 3: Borrowers ───────────────────────────────────────
    final borrowerSheet = excel['Borrowers'];
    final borrowerHeaders = [
      'Borrower ID',
      'Borrower Code',
      'Name',
      'Phone',
      'Address',
      'Active Loans',
      'Total Loans',
      'Total Lent (₹)',
      'Total Paid (₹)',
      'Pending Balance (₹)',
      'Status',
      'Notes',
      'Created At',
      'Updated At',
      'Sync ID',
      'Is Closed',
      'Is Deleted',
    ];
    _addHeader(borrowerSheet, borrowerHeaders);

    for (final b in borrowers) {
      final bId = b['id'] as int;
      final bLoans = loans.where((l) => l['borrower_id'] == bId && (l['is_deleted'] as int? ?? 0) == 0).toList();
      final bActiveLoans = bLoans.where((l) => l['status'] == 'active').toList();
      double bLent = 0;
      double bTotalDue = 0;
      for (final l in bLoans) {
        final p = (l['loan_amount'] as num).toDouble();
        final i = (l['interest_amount'] as num).toDouble();
        bLent += p;
        bTotalDue += (p + i);
      }
      final bLoanIds = bLoans.map((l) => l['id'] as int).toSet();
      double bPaid = 0;
      for (final p in payments) {
        if ((p['is_deleted'] as int? ?? 0) == 0 && bLoanIds.contains(p['loan_id'])) {
          bPaid += (p['amount'] as num).toDouble();
        }
      }
      final bPending = (bTotalDue - bPaid).clamp(0.0, double.infinity);
      final isClosed = (b['is_closed'] as int? ?? 0) == 1 || (bPending <= 0 && bActiveLoans.isEmpty);

      _addRow(borrowerSheet, [
        bId.toString(),
        b['borrower_code']?.toString() ?? '',
        b['name']?.toString() ?? '',
        b['phone']?.toString() ?? '',
        b['address']?.toString() ?? '',
        bActiveLoans.length.toString(),
        bLoans.length.toString(),
        bLent.toStringAsFixed(2),
        bPaid.toStringAsFixed(2),
        bPending.toStringAsFixed(2),
        isClosed ? 'CLOSED' : 'ACTIVE',
        b['notes']?.toString() ?? '',
        _formatEpochDate(b['created_at']),
        _formatEpochDate(b['updated_at']),
        b['sync_id']?.toString() ?? '',
        isClosed ? '1' : '0',
        (b['is_deleted'] as int? ?? 0).toString(),
      ]);
      handleRowWritten();
    }

    // ── SHEET 4: Loans ───────────────────────────────────────────
    final loanSheet = excel['Loans'];
    final loanHeaders = [
      'Loan ID',
      'Borrower Code',
      'Borrower Name',
      'Borrower ID',
      'Loan Date',
      'Principal Amount (₹)',
      'Interest Amount (₹)',
      'Total Due (₹)',
      'Total Paid (₹)',
      'Remaining Balance (₹)',
      'Status',
      'End Date',
      'Installment Days',
      'Notes',
      'Sync ID',
      'Borrower Sync ID',
      'Created At',
      'Updated At',
      'Is Deleted',
    ];
    _addHeader(loanSheet, loanHeaders);

    for (final l in loans) {
      final lId = l['id'] as int;
      final borrower = borrowerMap[l['borrower_id']];
      final bCode = borrower?['borrower_code']?.toString() ?? '-';
      final bName = borrower?['name']?.toString() ?? '-';
      final principal = (l['loan_amount'] as num).toDouble();
      final interest = (l['interest_amount'] as num).toDouble();
      final totalDue = principal + interest;

      double lPaid = 0;
      for (final p in payments) {
        if (p['loan_id'] == lId && (p['is_deleted'] as int? ?? 0) == 0) {
          lPaid += (p['amount'] as num).toDouble();
        }
      }
      final remaining = (totalDue - lPaid).clamp(0.0, double.infinity);
      final status = (l['status']?.toString() ?? 'active').toUpperCase();

      _addRow(loanSheet, [
        lId.toString(),
        bCode,
        bName,
        l['borrower_id']?.toString() ?? '',
        _formatDateOnly(l['loan_date']),
        principal.toStringAsFixed(2),
        interest.toStringAsFixed(2),
        totalDue.toStringAsFixed(2),
        lPaid.toStringAsFixed(2),
        remaining.toStringAsFixed(2),
        status,
        _formatDateOnly(l['end_date']),
        l['installment_days']?.toString() ?? '1',
        l['notes']?.toString() ?? '',
        l['sync_id']?.toString() ?? '',
        l['borrower_sync_id']?.toString() ?? '',
        _formatEpochDate(l['created_at']),
        _formatEpochDate(l['updated_at']),
        (l['is_deleted'] as int? ?? 0).toString(),
      ]);
      handleRowWritten();
    }

    // ── SHEET 5: Payments ────────────────────────────────────────
    final paymentSheet = excel['Payments'];
    final paymentHeaders = [
      'Payment ID',
      'Loan ID',
      'Borrower Code',
      'Borrower Name',
      'Payment Date',
      'Amount Paid (₹)',
      'Loan Principal (₹)',
      'Notes',
      'Sync ID',
      'Loan Sync ID',
      'Created At',
      'Updated At',
      'Is Deleted',
    ];
    _addHeader(paymentSheet, paymentHeaders);

    for (final p in payments) {
      final pId = p['id'] as int;
      final loan = loanMap[p['loan_id']];
      final borrower = loan != null ? borrowerMap[loan['borrower_id']] : null;
      final bCode = borrower?['borrower_code']?.toString() ?? '-';
      final bName = borrower?['name']?.toString() ?? '-';
      final loanPrincipal = (loan?['loan_amount'] as num?)?.toDouble() ?? 0.0;
      final pAmount = (p['amount'] as num).toDouble();

      _addRow(paymentSheet, [
        pId.toString(),
        p['loan_id']?.toString() ?? '',
        bCode,
        bName,
        _formatDateTime(p['payment_date']),
        pAmount.toStringAsFixed(2),
        loanPrincipal.toStringAsFixed(2),
        p['notes']?.toString() ?? '',
        p['sync_id']?.toString() ?? '',
        p['loan_sync_id']?.toString() ?? '',
        _formatEpochDate(p['created_at']),
        _formatEpochDate(p['updated_at']),
        (p['is_deleted'] as int? ?? 0).toString(),
      ]);
      handleRowWritten();
    }

    // ── SHEET 6: Expenses ────────────────────────────────────────
    final expenseSheet = excel['Expenses'];
    final expenseHeaders = [
      'Expense ID',
      'Date',
      'Category',
      'Amount (₹)',
      'Notes',
      'Sync ID',
      'Created At',
      'Updated At',
      'Is Deleted',
    ];
    _addHeader(expenseSheet, expenseHeaders);

    for (final e in expenses) {
      _addRow(expenseSheet, [
        e['id']?.toString() ?? '',
        _formatDateTime(e['expense_date']),
        e['category']?.toString() ?? '',
        ((e['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
        e['notes']?.toString() ?? '',
        e['sync_id']?.toString() ?? '',
        _formatEpochDate(e['created_at']),
        _formatEpochDate(e['updated_at']),
        (e['is_deleted'] as int? ?? 0).toString(),
      ]);
      handleRowWritten();
    }

    // ── SHEET 7: Investments ─────────────────────────────────────
    final investmentSheet = excel['Investments'];
    final investmentHeaders = [
      'Investment ID',
      'Date',
      'Amount (₹)',
      'Notes',
      'Sync ID',
      'Created At',
      'Updated At',
      'Is Deleted',
    ];
    _addHeader(investmentSheet, investmentHeaders);

    for (final i in investments) {
      _addRow(investmentSheet, [
        i['id']?.toString() ?? '',
        _formatDateOnly(i['inv_date']),
        ((i['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
        i['notes']?.toString() ?? '',
        i['sync_id']?.toString() ?? '',
        _formatEpochDate(i['created_at']),
        _formatEpochDate(i['updated_at']),
        (i['is_deleted'] as int? ?? 0).toString(),
      ]);
      handleRowWritten();
    }

    // ── SHEET 8: Service Costs ───────────────────────────────────
    final serviceCostsSheet = excel['Service Costs'];
    final serviceCostHeaders = [
      'Service Cost ID',
      'Date',
      'Amount (₹)',
      'Description',
      'Created By',
      'Sync ID',
      'Timestamp',
      'Is Deleted',
    ];
    _addHeader(serviceCostsSheet, serviceCostHeaders);

    for (final sc in serviceCosts) {
      _addRow(serviceCostsSheet, [
        sc['id']?.toString() ?? '',
        _formatDateTime(sc['dateCreated']),
        ((sc['amount'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2),
        sc['description']?.toString() ?? '',
        sc['createdBy']?.toString() ?? '',
        sc['sync_id']?.toString() ?? '',
        sc['timestamp']?.toString() ?? '',
        (sc['is_deleted'] as int? ?? 0).toString(),
      ]);
      handleRowWritten();
    }

    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Failed to encode Excel file.');
    final fileName = 'Credits_Backup_Report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

    final dir = await _getSaveDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  static Sheet? _getSheetCaseInsensitive(Excel excel, String name) {
    final nameNorm = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final key in excel.tables.keys) {
      final keyNorm = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (keyNorm == nameNorm) {
        return excel.tables[key];
      }
    }
    return null;
  }

  // ==========================================
  // IMPORT BACKUP & RESTORE
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

    if (_getSheetCaseInsensitive(excel, 'Metadata') == null &&
        _getSheetCaseInsensitive(excel, 'Overall Summary') == null &&
        _getSheetCaseInsensitive(excel, 'Summary') == null) {
      throw Exception('Invalid backup file structure: Missing Metadata/Summary sheet.');
    }
    if (_getSheetCaseInsensitive(excel, 'Borrowers') == null) {
      throw Exception('Invalid backup file structure: Missing Borrowers sheet.');
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
      'service_costs': getCount('Service Costs') > 0 ? getCount('Service Costs') : getCount('SERVICE_COSTS'),
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

  static final Map<String, List<String>> _columnAliases = {
    'id': ['id', 'borrowerid', 'loanid', 'paymentid', 'expenseid', 'investmentid', 'servicecostid'],
    'borrower_id': ['borrowerid', 'borrower'],
    'borrower_code': ['borrowercode', 'code', 'borrowerno', 'uniqueid'],
    'borrower_sync_id': ['borrowersyncid'],
    'loan_id': ['loanid', 'loan'],
    'loan_sync_id': ['loansyncid'],
    'loan_amount': ['loanamount', 'principalamount', 'principalamountrs', 'principal', 'loanamountrs'],
    'interest_amount': ['interestamount', 'interest', 'interestamountrs'],
    'loan_date': ['loandate', 'date'],
    'payment_date': ['paymentdate', 'date'],
    'expense_date': ['expensedate', 'date'],
    'inv_date': ['invdate', 'investmentdate', 'date'],
    'dateCreated': ['datecreated', 'date'],
    'createdBy': ['createdby'],
    'timestamp': ['timestamp'],
    'amount': ['amount', 'amountpaid', 'amountpaidrs', 'amountrs'],
    'installment_days': ['installmentdays'],
    'end_date': ['enddate'],
    'status': ['status'],
    'name': ['name', 'borrowername'],
    'phone': ['phone', 'phonenumber', 'mobile'],
    'address': ['address'],
    'notes': ['notes'],
    'description': ['description'],
    'category': ['category'],
    'sync_id': ['syncid'],
    'updated_at': ['updatedat'],
    'created_at': ['createdat'],
    'is_deleted': ['isdeleted'],
    'is_dummy': ['isdummy'],
    'is_closed': ['isclosed'],
  };

  static Map<String, dynamic> _sanitizeMap(Map<String, dynamic> map, List<String> validColumns) {
    final sanitized = <String, dynamic>{};

    final normalizedKeyMap = <String, String>{};
    for (final k in map.keys) {
      final normK = k.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      normalizedKeyMap[normK] = k;
    }

    for (final col in validColumns) {
      final normCol = col.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (normalizedKeyMap.containsKey(normCol)) {
        sanitized[col] = map[normalizedKeyMap[normCol]];
        continue;
      }

      // Check column aliases
      final aliases = _columnAliases[col];
      if (aliases != null) {
        for (final alias in aliases) {
          if (normalizedKeyMap.containsKey(alias)) {
            sanitized[col] = map[normalizedKeyMap[alias]];
            break;
          }
        }
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
    final sheetsToCount = ['Borrowers', 'Loans', 'Payments', 'Expenses', 'Investments', 'Service Costs', 'SERVICE_COSTS'];
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
        // Wipe local DB for replace mode
        final tables = ['payments', 'loans', 'borrowers', 'expenses', 'investments', 'service_costs'];
        for (final t in tables) {
          await txn.delete(t);
        }
      }

      // 1. Import Borrowers
      final bSheet = _getSheetCaseInsensitive(excel, 'Borrowers');
      Map<String, int> borrowerIdMap = {}; // Maps backup ID or code to new local ID
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

          final sanitized = _sanitizeMap(map, [
            'id', 'sync_id', 'borrower_code', 'name', 'phone', 'address', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted', 'is_dummy', 'is_closed'
          ]);

          final oldId = (sanitized['id'] ?? map['id'] ?? map['borrower_id'] ?? map['borrowerid'] ?? '').toString();
          final oldSyncId = (sanitized['sync_id'] ?? map['sync_id'] ?? map['syncid'] ?? '').toString();

          if (sanitized['created_at'] != null) {
            sanitized['created_at'] = _parseEpoch(sanitized['created_at']);
          }
          if (sanitized['updated_at'] != null) {
            sanitized['updated_at'] = _parseEpoch(sanitized['updated_at']);
          }
          if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
            sanitized['sync_id'] = const Uuid().v4();
          }
          sanitized['phone'] ??= '';
          if (sanitized['is_closed'] == null && map['status'] != null) {
            sanitized['is_closed'] = map['status'].toString().toUpperCase() == 'CLOSED' ? 1 : 0;
          } else if (sanitized['is_closed'] != null) {
            final valStr = sanitized['is_closed'].toString().toLowerCase();
            sanitized['is_closed'] = (valStr == '1' || valStr == 'true' || valStr == 'closed') ? 1 : 0;
          }

          // Duplicate detection via sync_id, internal id, or borrower_code
          List<Map<String, dynamic>> existing = [];
          if (oldSyncId.isNotEmpty) {
            existing = await txn.query('borrowers', where: 'sync_id = ?', whereArgs: [oldSyncId]);
          }
          if (existing.isEmpty && oldId.isNotEmpty) {
            final parsedId = int.tryParse(oldId);
            if (parsedId != null) {
              existing = await txn.query('borrowers', where: 'id = ?', whereArgs: [parsedId]);
            }
          }
          if (existing.isEmpty && sanitized['borrower_code'] != null && sanitized['borrower_code'].toString().isNotEmpty) {
            existing = await txn.query('borrowers', where: 'borrower_code = ?', whereArgs: [sanitized['borrower_code'].toString()]);
          }

          if (existing.isNotEmpty) {
            final exId = existing.first['id'] as int;
            if (oldId.isNotEmpty) borrowerIdMap[oldId] = exId;
            if (oldSyncId.isNotEmpty) borrowerIdMap[oldSyncId] = exId;
            if (sanitized['borrower_code'] != null) {
              borrowerIdMap['code_${sanitized['borrower_code']}'] = exId;
            }

            if (merge) {
              final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
              final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
              if (backupUpdatedAt > localUpdatedAt) {
                final updateData = Map<String, dynamic>.from(sanitized);
                updateData.remove('id');
                await txn.update('borrowers', updateData, where: 'id = ?', whereArgs: [exId]);
              }
            }
          } else {
            final insertData = Map<String, dynamic>.from(sanitized);
            if (merge || insertData['id'] == null) {
              insertData.remove('id');
            } else {
              final idCheck = await txn.query('borrowers', columns: ['id'], where: 'id = ?', whereArgs: [insertData['id']]);
              if (idCheck.isNotEmpty) {
                insertData.remove('id');
              }
            }
            final newId = await txn.insert('borrowers', insertData);
            if (oldId.isNotEmpty) borrowerIdMap[oldId] = newId;
            if (oldSyncId.isNotEmpty) borrowerIdMap[oldSyncId] = newId;
            if (sanitized['borrower_code'] != null) {
              borrowerIdMap['code_${sanitized['borrower_code']}'] = newId;
            }
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

          final sanitized = _sanitizeMap(map, [
            'id', 'sync_id', 'borrower_sync_id', 'loan_amount', 'interest_amount', 'loan_date',
            'installment_days', 'end_date', 'status', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);

          final oldId = (sanitized['id'] ?? map['id'] ?? map['loan_id'] ?? map['loanid'] ?? '').toString();
          final oldSyncId = (sanitized['sync_id'] ?? map['sync_id'] ?? map['syncid'] ?? '').toString();
          final oldBorrowerId = map['borrower_id']?.toString() ?? map['borrowerid']?.toString() ?? '';
          final bCode = map['borrower_code']?.toString() ?? map['borrowercode']?.toString() ?? '';
          final oldBorrowerSyncId = (sanitized['borrower_sync_id'] ?? map['borrower_sync_id'] ?? map['borrowersyncid'] ?? '').toString();

          if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
            sanitized['sync_id'] = const Uuid().v4();
          }

          // Resolve borrower_id
          sanitized['borrower_id'] = borrowerIdMap[oldBorrowerId]
              ?? (oldBorrowerSyncId.isNotEmpty ? borrowerIdMap[oldBorrowerSyncId] : null)
              ?? (bCode.isNotEmpty ? borrowerIdMap['code_$bCode'] : null)
              ?? int.tryParse(oldBorrowerId);

          if (sanitized['borrower_id'] == null && oldBorrowerSyncId.isNotEmpty) {
            final b = await txn.query('borrowers', where: 'sync_id = ?', whereArgs: [oldBorrowerSyncId]);
            if (b.isNotEmpty) sanitized['borrower_id'] = b.first['id'];
          }

          if (sanitized['borrower_id'] == null && bCode.isNotEmpty) {
            final b = await txn.query('borrowers', where: 'borrower_code = ?', whereArgs: [bCode]);
            if (b.isNotEmpty) sanitized['borrower_id'] = b.first['id'];
          }

          if (sanitized['borrower_id'] == null) continue; // Skip orphaned loan

          // Backfill borrower_sync_id
          if (sanitized['borrower_sync_id'] == null || sanitized['borrower_sync_id'].toString().isEmpty) {
            final b = await txn.query('borrowers', where: 'id = ?', whereArgs: [sanitized['borrower_id']]);
            if (b.isNotEmpty) sanitized['borrower_sync_id'] = b.first['sync_id'];
          }

          if (sanitized['loan_date'] != null) {
            sanitized['loan_date'] = DateParser.safeParse(sanitized['loan_date']).toIso8601String().replaceAll('T', ' ');
          } else {
            sanitized['loan_date'] = DateTime.now().toIso8601String().replaceAll('T', ' ');
          }
          sanitized['interest_amount'] ??= 0.0;

          if (sanitized['end_date'] != null && sanitized['end_date'].toString().trim().isNotEmpty && sanitized['end_date'] != '-') {
            sanitized['end_date'] = DateParser.safeParse(sanitized['end_date']).toIso8601String().replaceAll('T', ' ');
          } else {
            sanitized.remove('end_date');
          }

          if (sanitized['created_at'] != null) {
            sanitized['created_at'] = _parseEpoch(sanitized['created_at']);
          }
          if (sanitized['updated_at'] != null) {
            sanitized['updated_at'] = _parseEpoch(sanitized['updated_at']);
          }
          if (sanitized['status'] != null) {
            sanitized['status'] = sanitized['status'].toString().trim().toLowerCase();
          } else {
            sanitized['status'] = 'active';
          }

          // Duplicate detection via sync_id, id (with same borrower), or borrower_id + loan_date (prefix) + loan_amount
          List<Map<String, dynamic>> existing = [];
          if (oldSyncId.isNotEmpty) {
            existing = await txn.query('loans', where: 'sync_id = ?', whereArgs: [oldSyncId]);
          }
          if (existing.isEmpty && oldId.isNotEmpty) {
            final parsedId = int.tryParse(oldId);
            if (parsedId != null) {
              final byId = await txn.query('loans', where: 'id = ?', whereArgs: [parsedId]);
              if (byId.isNotEmpty && byId.first['borrower_id'] == sanitized['borrower_id']) {
                existing = byId;
              }
            }
          }
          if (existing.isEmpty && sanitized['borrower_id'] != null && sanitized['loan_amount'] != null) {
            final datePrefix = sanitized['loan_date'] != null && sanitized['loan_date'].toString().length >= 10
                ? sanitized['loan_date'].toString().substring(0, 10)
                : '';
            if (datePrefix.isNotEmpty) {
              existing = await txn.query('loans',
                  where: 'borrower_id = ? AND SUBSTR(REPLACE(loan_date, \'T\', \' \'), 1, 10) = ? AND ABS(loan_amount - ?) < 0.01',
                  whereArgs: [sanitized['borrower_id'], datePrefix, sanitized['loan_amount']]);
            }
          }

          if (existing.isNotEmpty) {
            final exId = existing.first['id'] as int;
            if (oldId.isNotEmpty) loanIdMap[oldId] = exId;
            if (oldSyncId.isNotEmpty) loanIdMap[oldSyncId] = exId;
            if (merge) {
              final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
              final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
              if (backupUpdatedAt > localUpdatedAt) {
                final updateData = Map<String, dynamic>.from(sanitized);
                updateData.remove('id');
                await txn.update('loans', updateData, where: 'id = ?', whereArgs: [exId]);
              }
            }
          } else {
            final insertData = Map<String, dynamic>.from(sanitized);
            if (merge || insertData['id'] == null) {
              insertData.remove('id');
            } else {
              final idCheck = await txn.query('loans', columns: ['id'], where: 'id = ?', whereArgs: [insertData['id']]);
              if (idCheck.isNotEmpty) {
                insertData.remove('id');
              }
            }
            final newId = await txn.insert('loans', insertData);
            if (oldId.isNotEmpty) loanIdMap[oldId] = newId;
            if (oldSyncId.isNotEmpty) loanIdMap[oldSyncId] = newId;
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

          final sanitized = _sanitizeMap(map, [
            'id', 'sync_id', 'loan_sync_id', 'amount', 'payment_date', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);

          final oldPaymentId = (sanitized['id'] ?? map['id'] ?? map['payment_id'] ?? map['paymentid'] ?? '').toString();
          final oldLoanId = map['loan_id']?.toString() ?? map['loanid']?.toString() ?? '';
          final oldSyncId = (sanitized['sync_id'] ?? map['sync_id'] ?? map['syncid'] ?? '').toString();
          final oldLoanSyncId = (sanitized['loan_sync_id'] ?? map['loan_sync_id'] ?? map['loansyncid'] ?? '').toString();

          if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
            sanitized['sync_id'] = const Uuid().v4();
          }

          sanitized['loan_id'] = loanIdMap[oldLoanId]
              ?? (oldLoanSyncId.isNotEmpty ? loanIdMap[oldLoanSyncId] : null)
              ?? int.tryParse(oldLoanId);

          if (sanitized['loan_id'] == null && oldLoanSyncId.isNotEmpty) {
            final l = await txn.query('loans', where: 'sync_id = ?', whereArgs: [oldLoanSyncId]);
            if (l.isNotEmpty) sanitized['loan_id'] = l.first['id'];
          }

          if (sanitized['loan_id'] == null) continue; // Skip orphaned payment

          if (sanitized['loan_sync_id'] == null || sanitized['loan_sync_id'].toString().isEmpty) {
            final l = await txn.query('loans', where: 'id = ?', whereArgs: [sanitized['loan_id']]);
            if (l.isNotEmpty) sanitized['loan_sync_id'] = l.first['sync_id'];
          }

          if (sanitized['payment_date'] != null) {
            sanitized['payment_date'] = DateParser.safeParse(sanitized['payment_date']).toIso8601String().replaceAll('T', ' ');
          }

          if (sanitized['created_at'] != null) {
            sanitized['created_at'] = _parseEpoch(sanitized['created_at']);
          }
          if (sanitized['updated_at'] != null) {
            sanitized['updated_at'] = _parseEpoch(sanitized['updated_at']);
          }

          // Duplicate detection
          List<Map<String, dynamic>> existing = [];
          if (oldSyncId.isNotEmpty) {
            existing = await txn.query('payments', where: 'sync_id = ?', whereArgs: [oldSyncId]);
          }
          if (existing.isEmpty && oldPaymentId.isNotEmpty) {
            final parsedId = int.tryParse(oldPaymentId);
            if (parsedId != null) {
              final byId = await txn.query('payments', where: 'id = ?', whereArgs: [parsedId]);
              if (byId.isNotEmpty && byId.first['loan_id'] == sanitized['loan_id']) {
                existing = byId;
              }
            }
          }
          if (existing.isEmpty && sanitized['loan_id'] != null && sanitized['amount'] != null) {
            final datePrefix = sanitized['payment_date'] != null && sanitized['payment_date'].toString().length >= 10
                ? sanitized['payment_date'].toString().substring(0, 10)
                : '';
            if (datePrefix.isNotEmpty) {
              existing = await txn.query('payments',
                  where: 'loan_id = ? AND SUBSTR(REPLACE(payment_date, \'T\', \' \'), 1, 10) = ? AND ABS(amount - ?) < 0.01',
                  whereArgs: [sanitized['loan_id'], datePrefix, sanitized['amount']]);
            }
          }

          if (existing.isNotEmpty) {
            if (merge) {
              final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
              final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
              if (backupUpdatedAt > localUpdatedAt) {
                final updateData = Map<String, dynamic>.from(sanitized);
                updateData.remove('id');
                await txn.update('payments', updateData, where: 'id = ?', whereArgs: [existing.first['id']]);
              }
            }
          } else {
            final insertData = Map<String, dynamic>.from(sanitized);
            if (merge || insertData['id'] == null) {
              insertData.remove('id');
            } else {
              final idCheck = await txn.query('payments', columns: ['id'], where: 'id = ?', whereArgs: [insertData['id']]);
              if (idCheck.isNotEmpty) {
                insertData.remove('id');
              }
            }
            await txn.insert('payments', insertData);
          }
        }
      }

      // 4. Import Expenses
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
              'id', 'sync_id', 'amount', 'expense_date', 'category', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            ]);

            final oldExpenseId = (sanitized['id'] ?? map['id'] ?? map['expense_id'] ?? map['expenseid'] ?? '').toString();
            final oldSyncId = (sanitized['sync_id'] ?? map['sync_id'] ?? map['syncid'] ?? '').toString();

            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
              sanitized['sync_id'] = const Uuid().v4();
            }

            if (sanitized['expense_date'] != null) {
              sanitized['expense_date'] = DateParser.safeParse(sanitized['expense_date']).toIso8601String().replaceAll('T', ' ');
            }
            if (sanitized['created_at'] != null) {
              sanitized['created_at'] = _parseEpoch(sanitized['created_at']);
            }
            if (sanitized['updated_at'] != null) {
              sanitized['updated_at'] = _parseEpoch(sanitized['updated_at']);
            }

            List<Map<String, dynamic>> existing = [];
            if (oldSyncId.isNotEmpty) {
              existing = await txn.query('expenses', where: 'sync_id = ?', whereArgs: [oldSyncId]);
            }
            if (existing.isEmpty && oldExpenseId.isNotEmpty) {
              final parsedId = int.tryParse(oldExpenseId);
              if (parsedId != null) {
                existing = await txn.query('expenses', where: 'id = ?', whereArgs: [parsedId]);
              }
            }
            if (existing.isEmpty && sanitized['created_at'] != null && (sanitized['created_at'] as int) > 0) {
              existing = await txn.query('expenses', where: 'created_at = ?', whereArgs: [sanitized['created_at']]);
            }
            if (existing.isNotEmpty) {
              if (merge) {
                final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
                final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
                if (backupUpdatedAt > localUpdatedAt) {
                  final updateData = Map<String, dynamic>.from(sanitized);
                  updateData.remove('id');
                  await txn.update('expenses', updateData, where: 'id = ?', whereArgs: [existing.first['id']]);
                }
              }
            } else {
              final insertData = Map<String, dynamic>.from(sanitized);
              if (merge || insertData['id'] == null) {
                insertData.remove('id');
              } else {
                final idCheck = await txn.query('expenses', columns: ['id'], where: 'id = ?', whereArgs: [insertData['id']]);
                if (idCheck.isNotEmpty) {
                  insertData.remove('id');
                }
              }
              await txn.insert('expenses', insertData);
            }
          }
        }
      }

      // 5. Import Investments
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
              'id', 'sync_id', 'amount', 'inv_date', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            ]);

            final oldInvId = (sanitized['id'] ?? map['id'] ?? map['investment_id'] ?? map['investmentid'] ?? '').toString();
            final oldSyncId = (sanitized['sync_id'] ?? map['sync_id'] ?? map['syncid'] ?? '').toString();

            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
              sanitized['sync_id'] = const Uuid().v4();
            }

            if (sanitized['inv_date'] != null) {
              sanitized['inv_date'] = DateParser.safeParse(sanitized['inv_date']).toIso8601String().replaceAll('T', ' ');
            }
            if (sanitized['created_at'] != null) {
              sanitized['created_at'] = _parseEpoch(sanitized['created_at']);
            }
            if (sanitized['updated_at'] != null) {
              sanitized['updated_at'] = _parseEpoch(sanitized['updated_at']);
            }

            List<Map<String, dynamic>> existing = [];
            if (oldSyncId.isNotEmpty) {
              existing = await txn.query('investments', where: 'sync_id = ?', whereArgs: [oldSyncId]);
            }
            if (existing.isEmpty && oldInvId.isNotEmpty) {
              final parsedId = int.tryParse(oldInvId);
              if (parsedId != null) {
                existing = await txn.query('investments', where: 'id = ?', whereArgs: [parsedId]);
              }
            }
            if (existing.isEmpty && sanitized['created_at'] != null && (sanitized['created_at'] as int) > 0) {
              existing = await txn.query('investments', where: 'created_at = ?', whereArgs: [sanitized['created_at']]);
            }
            if (existing.isNotEmpty) {
              if (merge) {
                final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
                final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
                if (backupUpdatedAt > localUpdatedAt) {
                  final updateData = Map<String, dynamic>.from(sanitized);
                  updateData.remove('id');
                  await txn.update('investments', updateData, where: 'id = ?', whereArgs: [existing.first['id']]);
                }
              }
            } else {
              final insertData = Map<String, dynamic>.from(sanitized);
              if (merge || insertData['id'] == null) {
                insertData.remove('id');
              } else {
                final idCheck = await txn.query('investments', columns: ['id'], where: 'id = ?', whereArgs: [insertData['id']]);
                if (idCheck.isNotEmpty) {
                  insertData.remove('id');
                }
              }
              await txn.insert('investments', insertData);
            }
          }
        }
      }

      // 6. Import Service Costs
      Future<void> importServiceCosts() async {
        final s = _getSheetCaseInsensitive(excel, 'Service Costs') ?? _getSheetCaseInsensitive(excel, 'SERVICE_COSTS');
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
              'id', 'sync_id', 'amount', 'description', 'dateCreated', 'createdBy', 'timestamp', 'is_deleted'
            ]);

            final oldCostId = (sanitized['id'] ?? map['id'] ?? map['servicecost_id'] ?? map['servicecostid'] ?? '').toString();
            final oldSyncId = (sanitized['sync_id'] ?? map['sync_id'] ?? map['syncid'] ?? '').toString();

            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
              sanitized['sync_id'] = const Uuid().v4();
            }

            if (sanitized['dateCreated'] != null) {
              sanitized['dateCreated'] = DateParser.safeParse(sanitized['dateCreated']).toIso8601String().replaceAll('T', ' ');
            }
            if (sanitized['timestamp'] != null) {
              sanitized['timestamp'] = _parseEpoch(sanitized['timestamp']);
            }

            List<Map<String, dynamic>> existing = [];
            if (oldSyncId.isNotEmpty) {
              existing = await txn.query('service_costs', where: 'sync_id = ?', whereArgs: [oldSyncId]);
            }
            if (existing.isEmpty && oldCostId.isNotEmpty) {
              final parsedId = int.tryParse(oldCostId);
              if (parsedId != null) {
                existing = await txn.query('service_costs', where: 'id = ?', whereArgs: [parsedId]);
              }
            }
            if (existing.isEmpty && sanitized['timestamp'] != null && (sanitized['timestamp'] as int) > 0) {
              existing = await txn.query('service_costs', where: 'timestamp = ?', whereArgs: [sanitized['timestamp']]);
            }
            if (existing.isNotEmpty) {
              if (merge) {
                final localTimestamp = existing.first['timestamp'] as int? ?? 0;
                final backupTimestamp = sanitized['timestamp'] as int? ?? 0;
                if (backupTimestamp > localTimestamp) {
                  final updateData = Map<String, dynamic>.from(sanitized);
                  updateData.remove('id');
                  await txn.update('service_costs', updateData, where: 'id = ?', whereArgs: [existing.first['id']]);
                }
              }
            } else {
              final insertData = Map<String, dynamic>.from(sanitized);
              if (merge || insertData['id'] == null) {
                insertData.remove('id');
              } else {
                final idCheck = await txn.query('service_costs', columns: ['id'], where: 'id = ?', whereArgs: [insertData['id']]);
                if (idCheck.isNotEmpty) {
                  insertData.remove('id');
                }
              }
              await txn.insert('service_costs', insertData);
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

    // 7. Restore configuration settings from Metadata sheet if available
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
      }
    } catch (restoreSettingsError) {
      debugPrint('[Restore] Warning: Failed to restore app settings from Metadata sheet: $restoreSettingsError');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_backup_blocked', false);
    await prefs.setBool('last_drive_check_success', true);
    await prefs.setString('local_db_last_modified_timestamp', DateTime.now().toUtc().toIso8601String());
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
        final header = headers[i];
        final normHeader = header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

        dynamic parsedVal;
        if (['id', 'borrowerid', 'loanid', 'paymentid', 'expenseid', 'investmentid', 'servicecostid', 'installmentdays', 'updatedat', 'createdat', 'issynced', 'isdeleted', 'timestamp', 'isclosed', 'isdummy'].contains(normHeader)) {
          parsedVal = int.tryParse(val) ?? 0;
        } else if (['loanamount', 'interestamount', 'amount', 'principalamount', 'principalamountrs', 'principal', 'amountpaid', 'amountpaidrs', 'totaldue', 'totalpaid', 'remainingbalance', 'balance'].contains(normHeader)) {
          parsedVal = double.tryParse(val) ?? 0.0;
        } else {
          parsedVal = val;
        }

        map[header] = parsedVal;
        map[normHeader] = parsedVal;
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
