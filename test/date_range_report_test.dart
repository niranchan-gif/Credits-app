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

  test('Test getDateRangeReport with sample data', () async {
    final dbHelper = DBHelper();
    
    // Clear and initialize DB
    final db = await dbHelper.database;
    await db.execute('DELETE FROM expenses');
    await db.execute('DELETE FROM loans');
    await db.execute('DELETE FROM payments');
    await db.execute('DELETE FROM borrowers');

    // Insert a dummy borrower
    final borrowerId = await db.insert('borrowers', {
      'borrower_code': 'B1',
      'name': 'Test Borrower',
      'phone': '1234567890',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'is_deleted': 0,
    });

    // Insert an expense
    await db.insert('expenses', {
      'amount': 100.0,
      'expense_date': '2026-06-11 12:00:00',
      'category': 'General',
      'notes': 'Test Note',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'is_deleted': 0,
    });

    // Insert a loan
    await db.insert('loans', {
      'borrower_id': borrowerId,
      'loan_amount': 1000.0,
      'interest_amount': 100.0,
      'loan_date': '2026-06-11 12:00:00',
      'status': 'active',
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
      'is_deleted': 0,
    });

    // Execute getDateRangeReport
    final start = DateTime(2026, 6, 1);
    final end = DateTime(2026, 6, 15);
    
    final report = await dbHelper.getDateRangeReport(start, end);
    
    expect(report['totalLent'], 1000.0);
    expect(report['totalExpenses'], 100.0);
    expect(report['transactions'].length, 2);
  });
}
