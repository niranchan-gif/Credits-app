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

  test('Test getDateRangeReport with sample data and ordering', () async {
    final dbHelper = DBHelper();
    
    // Clear and initialize DB
    final db = await dbHelper.database;
    await db.execute('DELETE FROM service_costs');
    await db.execute('DELETE FROM expenses');
    await db.execute('DELETE FROM payments');
    await db.execute('DELETE FROM loans');
    await db.execute('DELETE FROM borrowers');

    // Insert dummy borrowers
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

    // Insert loans
    final l1Id = await db.insert('loans', {
      'sync_id': 'l-sync-1',
      'borrower_id': b1Id,
      'loan_amount': 5000.0,
      'interest_amount': 500.0,
      'loan_date': '2026-06-11 00:00:00',
      'status': 'active',
      'created_at': 10000,
      'updated_at': 10000,
      'is_deleted': 0,
    });

    final l2Id = await db.insert('loans', {
      'sync_id': 'l-sync-2',
      'borrower_id': b2Id,
      'loan_amount': 3000.0,
      'interest_amount': 300.0,
      'loan_date': '2026-06-11 00:00:00',
      'status': 'active',
      'created_at': 20000,
      'updated_at': 20000,
      'is_deleted': 0,
    });

    // User inputs payments on 2026-06-11 in this exact sequence:
    // 1st: Borrower 102 pays 300 (created_at = 30000)
    await db.insert('payments', {
      'sync_id': 'p-sync-1',
      'loan_id': l2Id,
      'amount': 300.0,
      'payment_date': '2026-06-11 00:00:00',
      'created_at': 30000,
      'updated_at': 30000,
      'is_deleted': 0,
    });

    // 2nd: Borrower 101 pays 500 (created_at = 40000)
    await db.insert('payments', {
      'sync_id': 'p-sync-2',
      'loan_id': l1Id,
      'amount': 500.0,
      'payment_date': '2026-06-11 00:00:00',
      'created_at': 40000,
      'updated_at': 40000,
      'is_deleted': 0,
    });

    // 3rd: Expense of 150 (created_at = 50000)
    await db.insert('expenses', {
      'sync_id': 'e-sync-1',
      'amount': 150.0,
      'expense_date': '2026-06-11 00:00:00',
      'category': 'Petrol',
      'notes': 'Travel expense',
      'created_at': 50000,
      'updated_at': 50000,
      'is_deleted': 0,
    });

    // Execute getDateRangeReport for 2026-06-11
    final start = DateTime(2026, 6, 11);
    final end = DateTime(2026, 6, 11);
    
    final report = await dbHelper.getDateRangeReport(start, end);
    
    expect(report['totalLent'], 8000.0);
    expect(report['totalCollected'], 800.0);
    expect(report['totalExpenses'], 150.0);
    
    final txs = report['transactions'] as List<Map<String, dynamic>>;
    expect(txs.length, 5); // 2 loans + 2 payments + 1 expense

    // Verify order strictly matches user input order (created_at ascending):
    // Index 0: Loan 1 (created_at: 10000)
    expect(txs[0]['type'], 'Lent');
    expect(txs[0]['amount'], 5000.0);
    expect(txs[0]['created_at'], 10000);

    // Index 1: Loan 2 (created_at: 20000)
    expect(txs[1]['type'], 'Lent');
    expect(txs[1]['amount'], 3000.0);
    expect(txs[1]['created_at'], 20000);

    // Index 2: 1st payment entered (Borrower 102, created_at: 30000)
    expect(txs[2]['type'], 'Collected');
    expect(txs[2]['borrower_code'], '102');
    expect(txs[2]['amount'], 300.0);
    expect(txs[2]['created_at'], 30000);

    // Index 3: 2nd payment entered (Borrower 101, created_at: 40000)
    expect(txs[3]['type'], 'Collected');
    expect(txs[3]['borrower_code'], '101');
    expect(txs[3]['amount'], 500.0);
    expect(txs[3]['created_at'], 40000);

    // Index 4: Expense entered (created_at: 50000)
    expect(txs[4]['type'], 'Expense');
    expect(txs[4]['amount'], 150.0);
    expect(txs[4]['created_at'], 50000);
  });
}
