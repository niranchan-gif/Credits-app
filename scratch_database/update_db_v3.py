import os
import re

db_path = r'd:\vscode\credit\scratch_database\db_helper.dart'
with open(db_path, 'r', encoding='utf-8') as f:
    content = f.read()

if "import 'package:uuid/uuid.dart';" not in content:
    content = "import 'package:uuid/uuid.dart';\n" + content

content = re.sub(r'version:\s*13,', 'version: 14,', content)

# Inject sync_id into create tables
content = content.replace("is_dummy INTEGER NOT NULL DEFAULT 0\n      )", "is_dummy INTEGER NOT NULL DEFAULT 0,\n        sync_id TEXT NOT NULL DEFAULT ''\n      )")
content = content.replace("FOREIGN KEY (borrower_id) REFERENCES borrowers(id) ON DELETE CASCADE\n      )", "FOREIGN KEY (borrower_id) REFERENCES borrowers(id) ON DELETE CASCADE,\n        sync_id TEXT NOT NULL DEFAULT '',\n        borrower_sync_id TEXT\n      )")
content = content.replace("FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE\n      )", "FOREIGN KEY (loan_id) REFERENCES loans(id) ON DELETE CASCADE,\n        sync_id TEXT NOT NULL DEFAULT '',\n        loan_sync_id TEXT\n      )")
content = content.replace("is_deleted INTEGER NOT NULL DEFAULT 0\n      )\n    ''');\n\n    await db.execute('''\n      CREATE TABLE expenses", "is_deleted INTEGER NOT NULL DEFAULT 0,\n        sync_id TEXT NOT NULL DEFAULT ''\n      )\n    ''');\n\n    await db.execute('''\n      CREATE TABLE expenses")
content = content.replace("is_deleted INTEGER NOT NULL DEFAULT 0\n      )\n    ''');\n\n    await db.execute('''\n      CREATE TABLE service_costs", "is_deleted INTEGER NOT NULL DEFAULT 0,\n        sync_id TEXT NOT NULL DEFAULT ''\n      )\n    ''');\n\n    await db.execute('''\n      CREATE TABLE service_costs")
content = content.replace("is_deleted INTEGER NOT NULL DEFAULT 0\n      )\n    ''');\n\n    await db.execute('''\n      CREATE TABLE IF NOT EXISTS restore_meta", "is_deleted INTEGER NOT NULL DEFAULT 0,\n        sync_id TEXT NOT NULL DEFAULT ''\n      )\n    ''');\n\n    await db.execute('''\n      CREATE TABLE IF NOT EXISTS restore_meta")

# Add unique indexes in _createTables (right after the other indexes are created)
idx_block = '''    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_borrowers_sync_id ON borrowers(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_loans_sync_id ON loans(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_sync_id ON payments(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_expenses_sync_id ON expenses(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_investments_sync_id ON investments(sync_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_service_costs_sync_id ON service_costs(sync_id)');'''
content = content.replace(
    "await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_phone ON borrowers(phone)');",
    "await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_phone ON borrowers(phone)');\n" + idx_block,
    1
)

migration_block = '''
    if (oldVersion < 14) {
      debugPrint('DBHelper - Migrating to version 14 (Adding sync_id UUID to all tables)');
      final uuid = const Uuid();
      final tables = ['borrowers', 'loans', 'payments', 'investments', 'expenses', 'service_costs'];
      
      for (final table in tables) {
        final tblExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=''"
        )) ?? 0;
        
        if (tblExists > 0) {
          await db.execute('ALTER TABLE  ADD COLUMN sync_id TEXT NOT NULL DEFAULT ""');
          final rows = await db.query(table, columns: ['id']);
          for (final row in rows) {
            final id = row['id'];
            final generatedId = uuid.v4();
            await db.update(table, {'sync_id': generatedId}, where: 'id = ?', whereArgs: [id]);
          }
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx__sync_id ON (sync_id)');
        }
      }
      
      await db.execute('ALTER TABLE loans ADD COLUMN borrower_sync_id TEXT');
      await db.execute('ALTER TABLE payments ADD COLUMN loan_sync_id TEXT');
      
      debugPrint('DBHelper - Backfilling relational UUIDs...');
      await db.execute("UPDATE loans SET borrower_sync_id = (SELECT sync_id FROM borrowers WHERE id = loans.borrower_id)");
      await db.execute("UPDATE payments SET loan_sync_id = (SELECT sync_id FROM loans WHERE id = payments.loan_id)");
    }
'''
content = re.sub(
    r"(\s+debugPrint\('DBHelper [^\']+Migration completed successfully\.'\);\s+\})",
    migration_block + r"\1",
    content
)

with open(db_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('DBHelper updated accurately.')
