import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:credit/database/db_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  test('Test getTotalCollectedOnDate and getLastPaymentBorrowerCode', () async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;

    await db.execute('DELETE FROM payments');
    await db.execute('DELETE FROM loans');
    await db.execute('DELETE FROM borrowers');

    // Insert borrower 1
    final b1Id = await db.insert('borrowers', {
      'sync_id': 'b-sync-1',
      'borrower_code': '101',
      'name': 'Borrower 101',
      'phone': '1234567890',
      'created_at': 1000,
      'updated_at': 1000,
      'is_deleted': 0,
      'is_dummy': 0,
    });

    // Insert borrower 2
    final b2Id = await db.insert('borrowers', {
      'sync_id': 'b-sync-2',
      'borrower_code': '102',
      'name': 'Borrower 102',
      'phone': '9876543210',
      'created_at': 2000,
      'updated_at': 2000,
      'is_deleted': 0,
      'is_dummy': 0,
    });

    // Insert active loans
    final l1Id = await db.insert('loans', {
      'sync_id': 'loan-sync-1',
      'borrower_id': b1Id,
      'loan_amount': 5000.0,
      'interest_amount': 500.0,
      'loan_date': '2026-09-13 10:00:00',
      'status': 'active',
      'created_at': 1000,
      'updated_at': 1000,
      'is_deleted': 0,
    });

    final l2Id = await db.insert('loans', {
      'sync_id': 'loan-sync-2',
      'borrower_id': b2Id,
      'loan_amount': 3000.0,
      'interest_amount': 300.0,
      'loan_date': '2026-09-13 10:00:00',
      'status': 'active',
      'created_at': 2000,
      'updated_at': 2000,
      'is_deleted': 0,
    });

    // Test total before any payments
    final today = DateTime(2026, 9, 13);
    final tomorrow = DateTime(2026, 9, 14);

    expect(await dbHelper.getTotalCollectedOnDate(today), 0.0);
    expect(await dbHelper.getLastPaymentBorrowerCode(), isNull);

    // Insert payment for borrower 1 on 2026-09-13
    await db.insert('payments', {
      'sync_id': 'pay-1',
      'loan_id': l1Id,
      'amount': 500.0,
      'payment_date': '2026-09-13T11:30:00.000',
      'created_at': 3000,
      'updated_at': 3000,
      'is_deleted': 0,
    });

    expect(await dbHelper.getTotalCollectedOnDate(today), 500.0);
    expect(await dbHelper.getLastPaymentBorrowerCode(), '101');

    // Insert another payment for borrower 2 on 2026-09-13
    await db.insert('payments', {
      'sync_id': 'pay-2',
      'loan_id': l2Id,
      'amount': 300.0,
      'payment_date': '2026-09-13 14:00:00',
      'created_at': 4000,
      'updated_at': 4000,
      'is_deleted': 0,
    });

    // Today's total is now 800.0
    expect(await dbHelper.getTotalCollectedOnDate(today), 800.0);
    // Last payment entered is now borrower 102
    expect(await dbHelper.getLastPaymentBorrowerCode(), '102');

    // Test getDateRangeReport for today (day transactions)
    final report = await dbHelper.getDateRangeReport(today, today);
    expect(report['totalCollected'], 800.0);
    final txs = report['transactions'] as List;
    // 2 loans (Lent) + 2 payments (Collected) = 4 transactions
    expect(txs.length, 4);
    expect(txs.any((t) => t['borrower_code'] == '101' && t['amount'] == 500.0 && t['type'] == 'Collected'), isTrue);
    expect(txs.any((t) => t['borrower_code'] == '102' && t['amount'] == 300.0 && t['type'] == 'Collected'), isTrue);
    expect(txs.any((t) => t['borrower_code'] == '101' && t['type'] == 'Lent'), isTrue);
    expect(txs.any((t) => t['borrower_code'] == '102' && t['type'] == 'Lent'), isTrue);

    // On tomorrow, transactions list is empty
    final tomorrowReport = await dbHelper.getDateRangeReport(tomorrow, tomorrow);
    expect(tomorrowReport['totalCollected'], 0.0);
    expect((tomorrowReport['transactions'] as List).isEmpty, isTrue);
  });
}
