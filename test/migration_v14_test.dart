import 'package:flutter_test/flutter_test.dart';
import 'package:credit/database/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Migration v14 should generate UUIDs for sync_id', () async {
    final dbHelper = DBHelper();
    final db = await dbHelper.database;
    
    // Verify sync_id column exists and has UUIDs
    final borrowers = await db.query('borrowers');
    for (final b in borrowers) {
      expect(b.containsKey('sync_id'), isTrue, reason: 'borrowers missing sync_id');
      expect(b['sync_id'].toString().isNotEmpty, isTrue, reason: 'borrowers sync_id is empty');
    }

    final loans = await db.query('loans');
    for (final l in loans) {
      expect(l.containsKey('sync_id'), isTrue);
      expect(l.containsKey('borrower_sync_id'), isTrue);
      expect(l['sync_id'].toString().isNotEmpty, isTrue);
    }
    
    final payments = await db.query('payments');
    for (final p in payments) {
      expect(p.containsKey('sync_id'), isTrue);
      expect(p.containsKey('loan_sync_id'), isTrue);
    }
    
    print('Migration validation passed successfully!');
  });
}
