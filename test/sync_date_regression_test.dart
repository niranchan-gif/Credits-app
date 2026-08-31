import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:credit/database/db_helper.dart';
import 'package:credit/services/excel_backup_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Clear DB between tests if needed, or use a new DB path.
    // DBHelper is a singleton, so we can just delete the db file or clear tables.
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    await db.delete('payments');
    await db.delete('loans');
    await db.delete('borrowers');
  });

  test('Date changed backwards: PC has newer updatedAt but older transactionDate', () async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    final syncId = const Uuid().v4();
    final loanSyncId = const Uuid().v4();
    final borrowerSyncId = const Uuid().v4();

    // 1. Phone has record: Date = 15 Aug, updatedAt = 1000
    await db.insert('borrowers', {
      'id': 1, 'sync_id': borrowerSyncId, 'borrower_code': 'B1', 'name': 'Test', 'phone': '1234567890',
      'updated_at': 1000, 'created_at': 1000
    });
    await db.insert('loans', {
      'id': 1, 'sync_id': loanSyncId, 'borrower_id': 1, 'loan_amount': 100, 
      'updated_at': 1000, 'created_at': 1000, 'status': 'active'
    });
    await db.insert('payments', {
      'id': 1, 'sync_id': syncId, 'loan_id': 1, 'amount': 50.0, 
      'payment_date': '2023-08-15 00:00:00.000', 'updated_at': 1000, 'created_at': 1000
    });

    // 2. PC (backup) has edited record: Date = 9 Aug (older), updatedAt = 2000 (newer)
    final excel = Excel.createExcel();
    final metaSheet = excel['Metadata'];
    metaSheet.appendRow([TextCellValue('Key'), TextCellValue('Value')]);
    metaSheet.appendRow([TextCellValue('schema_version'), TextCellValue('14')]);
    
    final bSheet = excel['Borrowers'];
    bSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('borrower_code'), TextCellValue('name'), TextCellValue('phone'), TextCellValue('updated_at'), TextCellValue('created_at')]);
    bSheet.appendRow([IntCellValue(1), TextCellValue(borrowerSyncId), TextCellValue('B1'), TextCellValue('Test'), TextCellValue('1234567890'), IntCellValue(1000), IntCellValue(1000)]);
    
    final lSheet = excel['Loans'];
    lSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('borrower_id'), TextCellValue('loan_amount'), TextCellValue('interest_amount'), TextCellValue('updated_at'), TextCellValue('created_at'), TextCellValue('status')]);
    lSheet.appendRow([IntCellValue(1), TextCellValue(loanSyncId), IntCellValue(1), DoubleCellValue(100.0), DoubleCellValue(0.0), IntCellValue(1000), IntCellValue(1000), TextCellValue('active')]);
    
    final pSheet = excel['Payments'];
    pSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('loan_id'), TextCellValue('amount'), TextCellValue('payment_date'), TextCellValue('updated_at'), TextCellValue('created_at'), TextCellValue('is_deleted')]);
    pSheet.appendRow([IntCellValue(1), TextCellValue(syncId), IntCellValue(1), DoubleCellValue(50.0), TextCellValue('2023-08-09T00:00:00.000'), IntCellValue(2000), IntCellValue(1000), IntCellValue(0)]);
    
    final bytes = excel.encode()!;

    // 3. Import (Merge)
    await ExcelBackupService.importBackup(null, fileBytes: bytes, merge: true);

    // 4. Verify phone accepted the PC's change because backup.updatedAt (2000) > local.updatedAt (1000)
    final payments = await db.query('payments');
    expect(payments.length, 1);
    expect(payments.first['payment_date'], contains('2023-08-09'));
    expect(payments.first['updated_at'], 2000);
  });

  test('PC to Phone restore (Merge: false)', () async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    final syncId = const Uuid().v4();

    // 1. Phone has some junk data
    await db.insert('borrowers', {
      'id': 99, 'sync_id': 'junk_b', 'borrower_code': 'J1', 'name': 'Junk', 'phone': '000',
      'updated_at': 500, 'created_at': 500
    });
    await db.insert('loans', {
      'id': 99, 'sync_id': 'junk_l', 'borrower_id': 99, 'loan_amount': 100, 'interest_amount': 0,
      'updated_at': 500, 'created_at': 500, 'status': 'active'
    });
    await db.insert('payments', {
      'id': 99, 'sync_id': 'junk', 'loan_id': 99, 'amount': 999.0, 
      'payment_date': '2023-01-01 00:00:00.000', 'updated_at': 500, 'created_at': 500
    });

    // 2. PC has a valid backup
    final excel = Excel.createExcel();
    final metaSheet = excel['Metadata'];
    metaSheet.appendRow([TextCellValue('Key'), TextCellValue('Value')]);
    metaSheet.appendRow([TextCellValue('schema_version'), TextCellValue('14')]);
    
    final bSheet = excel['Borrowers'];
    bSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('borrower_code'), TextCellValue('name')]);
    bSheet.appendRow([IntCellValue(1), TextCellValue('b-sync'), TextCellValue('B1'), TextCellValue('Test')]);
    
    final lSheet = excel['Loans'];
    lSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('borrower_id'), TextCellValue('loan_amount'), TextCellValue('interest_amount')]);
    lSheet.appendRow([IntCellValue(1), TextCellValue('l-sync'), IntCellValue(1), DoubleCellValue(100.0), DoubleCellValue(0.0)]);
    
    final pSheet = excel['Payments'];
    pSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('loan_id'), TextCellValue('amount'), TextCellValue('payment_date'), TextCellValue('updated_at'), TextCellValue('created_at')]);
    pSheet.appendRow([IntCellValue(1), TextCellValue(syncId), IntCellValue(1), DoubleCellValue(50.0), TextCellValue('2023-08-09T00:00:00.000'), IntCellValue(2000), IntCellValue(1000)]);
    
    final bytes = excel.encode()!;

    // 3. Import (Restore / Merge = false)
    await ExcelBackupService.importBackup(null, fileBytes: bytes, merge: false);

    // 4. Verify local DB was wiped and replaced with PC data
    final payments = await db.query('payments');
    expect(payments.length, 1);
    expect(payments.first['id'], 1);
    expect(payments.first['sync_id'], syncId);
    expect(payments.first['payment_date'], contains('2023-08-09'));
  });

  test('Local edit wins if local updatedAt is newer than backup', () async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    final syncId = const Uuid().v4();
    final loanSyncId = const Uuid().v4();
    final borrowerSyncId = const Uuid().v4();

    // 1. Phone has record edited today: Date = 9 Aug, updatedAt = 3000
    await db.insert('borrowers', {
      'id': 1, 'sync_id': borrowerSyncId, 'borrower_code': 'B1', 'name': 'Test', 'phone': '1234567890',
      'updated_at': 1000, 'created_at': 1000
    });
    await db.insert('loans', {
      'id': 1, 'sync_id': loanSyncId, 'borrower_id': 1, 'loan_amount': 100, 
      'updated_at': 1000, 'created_at': 1000, 'status': 'active'
    });
    await db.insert('payments', {
      'id': 1, 'sync_id': syncId, 'loan_id': 1, 'amount': 50.0, 
      'payment_date': '2023-08-09 00:00:00.000', 'updated_at': 3000, 'created_at': 1000
    });

    // 2. PC (backup) is OLD: Date = 15 Aug, updatedAt = 2000
    final excel = Excel.createExcel();
    final metaSheet = excel['Metadata'];
    metaSheet.appendRow([TextCellValue('Key'), TextCellValue('Value')]);
    metaSheet.appendRow([TextCellValue('schema_version'), TextCellValue('14')]);
    
    final pSheet = excel['Payments'];
    pSheet.appendRow([TextCellValue('id'), TextCellValue('sync_id'), TextCellValue('loan_id'), TextCellValue('amount'), TextCellValue('payment_date'), TextCellValue('updated_at'), TextCellValue('created_at'), TextCellValue('is_deleted')]);
    pSheet.appendRow([IntCellValue(1), TextCellValue(syncId), IntCellValue(1), DoubleCellValue(50.0), TextCellValue('2023-08-15T00:00:00.000'), IntCellValue(2000), IntCellValue(1000), IntCellValue(0)]);
    
    final bytes = excel.encode()!;

    // 3. Import (Merge)
    await ExcelBackupService.importBackup(null, fileBytes: bytes, merge: true);

    // 4. Verify phone REJECTED the PC's change because local.updatedAt (3000) > backup.updatedAt (2000)
    final payments = await db.query('payments');
    expect(payments.length, 1);
    expect(payments.first['payment_date'], contains('2023-08-09'));
    expect(payments.first['updated_at'], 3000);
  });
}
