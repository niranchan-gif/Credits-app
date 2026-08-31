import os
import re

db_path = r'd:\vscode\credit\scratch_database\db_helper.dart'
with open(db_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Import uuid
if 'import \'package:uuid/uuid.dart\';' not in content:
    content = 'import \'package:uuid/uuid.dart\';\n' + content

# 2. Version bump
content = re.sub(r'version:\s*13,', 'version: 14,', content)

# 3. Add sync_id to CREATE TABLE
tables = ['borrowers', 'loans', 'payments', 'expenses', 'investments', 'service_costs']
for table in tables:
    # borrowers
    if table == 'borrowers':
        content = re.sub(r"('CREATE TABLE borrowers \([^)]*)(is_dummy INTEGER NOT NULL DEFAULT 0)([^)]*\)')", r"\1\2,\n          sync_id TEXT NOT NULL DEFAULT ''\3", content)
    elif table == 'loans':
        content = re.sub(r"('CREATE TABLE loans \([^)]*)(is_deleted INTEGER NOT NULL DEFAULT 0)([^)]*\)')", r"\1\2,\n          sync_id TEXT NOT NULL DEFAULT '',\n          borrower_sync_id TEXT\3", content)
    elif table == 'payments':
        content = re.sub(r"('CREATE TABLE payments \([^)]*)(is_deleted INTEGER NOT NULL DEFAULT 0)([^)]*\)')", r"\1\2,\n          sync_id TEXT NOT NULL DEFAULT '',\n          loan_sync_id TEXT\3", content)
    elif table == 'expenses':
        content = re.sub(r"('CREATE TABLE expenses \([^)]*)(is_deleted INTEGER NOT NULL DEFAULT 0)([^)]*\)')", r"\1\2,\n          sync_id TEXT NOT NULL DEFAULT ''\3", content)
    elif table == 'investments':
        content = re.sub(r"('CREATE TABLE investments \([^)]*)(is_deleted INTEGER NOT NULL DEFAULT 0)([^)]*\)')", r"\1\2,\n          sync_id TEXT NOT NULL DEFAULT ''\3", content)
    elif table == 'service_costs':
        content = re.sub(r"('CREATE TABLE service_costs \([^)]*)(is_deleted INTEGER NOT NULL DEFAULT 0)([^)]*\)')", r"\1\2,\n          sync_id TEXT NOT NULL DEFAULT ''\3", content)

# Add unique indexes in _createTables
if 'idx_borrowers_sync_id' not in content:
    idx_block = """
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_borrowers_sync_id ON borrowers(sync_id)');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_loans_sync_id ON loans(sync_id)');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_sync_id ON payments(sync_id)');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_expenses_sync_id ON expenses(sync_id)');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_investments_sync_id ON investments(sync_id)');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_service_costs_sync_id ON service_costs(sync_id)');
    """
    content = content.replace("await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_phone ON borrowers(phone)');", "await db.execute('CREATE INDEX IF NOT EXISTS idx_borrowers_phone ON borrowers(phone)');" + idx_block)


# 4. Add V14 Migration block in _upgradeTables
if 'oldVersion < 14' not in content:
    migration_block = """
    // Migrate to version 14: Add sync_id and relational sync_ids
    if (oldVersion < 14) {
      debugPrint('DBHelper - Migrating to version 14 (Adding sync_id UUID to all tables)');
      final uuid = const Uuid();
      final tables = ['borrowers', 'loans', 'payments', 'investments', 'expenses', 'service_costs'];
      
      for (final table in tables) {
        final tblExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=''"
        )) ?? 0;
        
        if (tblExists > 0) {
          // Add primary sync_id
          await db.execute('ALTER TABLE  ADD COLUMN sync_id TEXT NOT NULL DEFAULT ""');
          
          // Generate UUID for each row
          final rows = await db.query(table, columns: ['id']);
          for (final row in rows) {
            final id = row['id'];
            final generatedId = uuid.v4();
            await db.update(table, {'sync_id': generatedId}, where: 'id = ?', whereArgs: [id]);
          }
          
          await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx__sync_id ON (sync_id)');
        }
      }
      
      // Add relational columns
      await db.execute('ALTER TABLE loans ADD COLUMN borrower_sync_id TEXT');
      await db.execute('ALTER TABLE payments ADD COLUMN loan_sync_id TEXT');
      
      // Stage 2: Relationship Migration (Backfill foreign sync_ids)
      debugPrint('DBHelper - Backfilling relational UUIDs...');
      await db.execute('''
        UPDATE loans 
        SET borrower_sync_id = (SELECT sync_id FROM borrowers WHERE id = loans.borrower_id)
      ''');
      
      await db.execute('''
        UPDATE payments 
        SET loan_sync_id = (SELECT sync_id FROM loans WHERE id = payments.loan_id)
      ''');
    }
"""
    # Insert right before debugPrint('DBHelper - Migration completed successfully.');
    content = content.replace("debugPrint('DBHelper \u2500 Migration completed successfully.');", migration_block + "\n      debugPrint('DBHelper \u2500 Migration completed successfully.');")


with open(db_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('DBHelper updated.')
