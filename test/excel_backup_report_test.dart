import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:credit/database/db_helper.dart';
import 'package:credit/services/excel_backup_service.dart';

String _extractCellValue(dynamic cellVal) {
  if (cellVal == null) return '';
  if (cellVal is TextCellValue) return cellVal.value.toString();
  if (cellVal is IntCellValue) return cellVal.value.toString();
  if (cellVal is DoubleCellValue) return cellVal.value.toString();
  return cellVal.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider_windows'),
      (MethodCall methodCall) async => Directory.systemTemp.path,
    );
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    await db.delete('payments');
    await db.delete('loans');
    await db.delete('borrowers');
    await db.delete('expenses');
    await db.delete('investments');
    await db.delete('service_costs');
  });

  test('Export readable Excel report and restore full backup', () async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;

    // 1. Insert rich sample data
    final b1Id = await db.insert('borrowers', {
      'sync_id': 'b-sync-1',
      'borrower_code': '101',
      'name': 'Alice Smith',
      'phone': '9876543210',
      'address': '123 Market St',
      'notes': 'VIP Customer',
      'created_at': 1700000000000,
      'updated_at': 1700000000000,
      'is_deleted': 0,
      'is_dummy': 0,
    });

    final b2Id = await db.insert('borrowers', {
      'sync_id': 'b-sync-2',
      'borrower_code': '102',
      'name': 'Bob Johnson',
      'phone': '9123456780',
      'address': '456 Elm St',
      'notes': 'Regular borrower',
      'created_at': 1700000001000,
      'updated_at': 1700000001000,
      'is_deleted': 0,
      'is_dummy': 0,
    });

    final l1Id = await db.insert('loans', {
      'sync_id': 'l-sync-1',
      'borrower_id': b1Id,
      'loan_amount': 10000.0,
      'interest_amount': 1000.0,
      'loan_date': '2026-09-01 10:00:00',
      'end_date': '2026-10-01 10:00:00',
      'status': 'active',
      'installment_days': 30,
      'notes': 'First business loan',
      'created_at': 1700000002000,
      'updated_at': 1700000002000,
      'is_deleted': 0,
    });

    final l2Id = await db.insert('loans', {
      'sync_id': 'l-sync-2',
      'borrower_id': b2Id,
      'loan_amount': 5000.0,
      'interest_amount': 500.0,
      'loan_date': '2026-08-01 09:00:00',
      'end_date': '2026-09-01 09:00:00',
      'status': 'closed',
      'installment_days': 30,
      'notes': 'Completed loan',
      'created_at': 1700000003000,
      'updated_at': 1700000003000,
      'is_deleted': 0,
    });

    final p1Id = await db.insert('payments', {
      'sync_id': 'p-sync-1',
      'loan_id': l1Id,
      'amount': 3000.0,
      'payment_date': '2026-09-05 14:00:00',
      'notes': 'First installment',
      'created_at': 1700000004000,
      'updated_at': 1700000004000,
      'is_deleted': 0,
    });

    final e1Id = await db.insert('expenses', {
      'sync_id': 'e-sync-1',
      'amount': 250.0,
      'category': 'Office Supplies',
      'expense_date': '2026-09-02 11:00:00',
      'notes': 'Stationery and ink',
      'created_at': 1700000005000,
      'updated_at': 1700000005000,
      'is_deleted': 0,
    });

    final inv1Id = await db.insert('investments', {
      'sync_id': 'inv-sync-1',
      'amount': 50000.0,
      'inv_date': '2026-08-15 08:00:00',
      'notes': 'Initial business capital',
      'created_at': 1700000006000,
      'updated_at': 1700000006000,
      'is_deleted': 0,
    });

    final sc1Id = await db.insert('service_costs', {
      'sync_id': 'sc-sync-1',
      'amount': 150.0,
      'description': 'Motorbike petrol',
      'dateCreated': '2026-09-03 16:00:00',
      'createdBy': 'Agent 1',
      'timestamp': 1700000007000,
      'is_deleted': 0,
    });

    // 2. Perform export
    final exportedPath = await ExcelBackupService.exportFullBackup();
    expect(File(exportedPath).existsSync(), isTrue);

    // 3. Inspect generated Excel workbook
    final fileBytes = await File(exportedPath).readAsBytes();
    final excel = Excel.decodeBytes(fileBytes);

    final expectedSheets = [
      'Overall Summary',
      'Borrowers',
      'Loans',
      'Payments',
      'Expenses',
      'Investments',
      'Service Costs',
      'Metadata'
    ];
    for (final sheetName in expectedSheets) {
      final hasSheet = excel.tables.keys.any((k) => k.toLowerCase() == sheetName.toLowerCase());
      expect(hasSheet, isTrue, reason: 'Missing sheet $sheetName in exported Excel');
    }

    // Check Overall Summary sheet content
    final summarySheet = excel.tables['Overall Summary']!;
    final summaryRows = summarySheet.rows.map((r) => r.map((c) => _extractCellValue(c?.value)).toList()).toList();
    final summaryText = summaryRows.map((r) => r.join(' | ')).join('\n');
    expect(summaryText, contains('Credits'));
    expect(summaryText, contains('Overall Summary'));
    expect(summaryText, contains('On Hand Cash'));
    expect(summaryText, contains('Total Invested'));
    expect(summaryText, contains('To Recover'));
    expect(summaryText, contains('Collected'));
    expect(summaryText, contains('Pending'));

    // Check Borrowers sheet columns and content
    final borrowersSheet = excel.tables['Borrowers']!;
    final bHeaders = borrowersSheet.rows[0].map((c) => _extractCellValue(c?.value)).toList();
    expect(bHeaders, contains('Borrower Code'));
    expect(bHeaders, contains('Name'));
    expect(bHeaders, contains('Pending Balance (₹)'));

    final bRowsText = borrowersSheet.rows.map((r) => r.map((c) => _extractCellValue(c?.value)).join(' | ')).join('\n');
    expect(bRowsText, contains('Alice Smith'));
    expect(bRowsText, contains('Bob Johnson'));

    // Check previewImport
    final preview = await ExcelBackupService.previewImport(exportedPath);
    expect(preview['borrowers'], 2);
    expect(preview['loans'], 2);
    expect(preview['payments'], 1);
    expect(preview['expenses'], 1);
    expect(preview['investments'], 1);
    expect(preview['service_costs'], 1);

    // 4. Clear database to simulate restore on a clean device
    await db.delete('payments');
    await db.delete('loans');
    await db.delete('borrowers');
    await db.delete('expenses');
    await db.delete('investments');
    await db.delete('service_costs');

    expect((await db.query('borrowers')).length, 0);
    expect((await db.query('loans')).length, 0);
    expect((await db.query('payments')).length, 0);
    expect((await db.query('expenses')).length, 0);
    expect((await db.query('investments')).length, 0);
    expect((await db.query('service_costs')).length, 0);

    // 5. Restore from the human-readable Excel report backup
    await ExcelBackupService.importBackup(exportedPath, merge: false);

    // 6. Verify 100% data fidelity after restore
    final restoredBorrowers = await db.query('borrowers', orderBy: 'id ASC');
    expect(restoredBorrowers.length, 2);
    expect(restoredBorrowers[0]['borrower_code'], '101');
    expect(restoredBorrowers[0]['name'], 'Alice Smith');
    expect(restoredBorrowers[0]['phone'], '9876543210');
    expect(restoredBorrowers[0]['address'], '123 Market St');
    expect(restoredBorrowers[0]['notes'], 'VIP Customer');
    expect(restoredBorrowers[1]['borrower_code'], '102');
    expect(restoredBorrowers[1]['name'], 'Bob Johnson');

    final restoredLoans = await db.query('loans', orderBy: 'id ASC');
    expect(restoredLoans.length, 2);
    expect(restoredLoans[0]['loan_amount'], 10000.0);
    expect(restoredLoans[0]['interest_amount'], 1000.0);
    expect(restoredLoans[0]['status'], 'active');
    expect(restoredLoans[0]['borrower_id'], restoredBorrowers[0]['id']);

    final restoredPayments = await db.query('payments', orderBy: 'id ASC');
    expect(restoredPayments.length, 1);
    expect(restoredPayments[0]['amount'], 3000.0);
    expect(restoredPayments[0]['notes'], 'First installment');
    expect(restoredPayments[0]['loan_id'], restoredLoans[0]['id']);

    final restoredExpenses = await db.query('expenses', orderBy: 'id ASC');
    expect(restoredExpenses.length, 1);
    expect(restoredExpenses[0]['amount'], 250.0);
    expect(restoredExpenses[0]['category'], 'Office Supplies');

    final restoredInvestments = await db.query('investments', orderBy: 'id ASC');
    expect(restoredInvestments.length, 1);
    expect(restoredInvestments[0]['amount'], 50000.0);
    expect(restoredInvestments[0]['notes'], 'Initial business capital');

    final restoredServiceCosts = await db.query('service_costs', orderBy: 'id ASC');
    expect(restoredServiceCosts.length, 1);
    expect(restoredServiceCosts[0]['amount'], 150.0);
    expect(restoredServiceCosts[0]['description'], 'Motorbike petrol');
  });
}
