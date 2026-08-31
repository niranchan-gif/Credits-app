import os
import re

db_path = r'd:\vscode\credit\scratch_database\db_helper.dart'
with open(db_path, 'r', encoding='utf-8') as f:
    content = f.read()

# Replace ALTER TABLE ADD COLUMN with try-catch blocks
content = content.replace("await db.execute('ALTER TABLE  ADD COLUMN sync_id TEXT NOT NULL DEFAULT \"\"');", '''try {
            await db.execute('ALTER TABLE  ADD COLUMN sync_id TEXT NOT NULL DEFAULT ""');
          } catch (e) {
            debugPrint('Column sync_id already exists in ');
          }''')
content = content.replace("await db.execute('ALTER TABLE loans ADD COLUMN borrower_sync_id TEXT');", '''try {
        await db.execute('ALTER TABLE loans ADD COLUMN borrower_sync_id TEXT');
      } catch (e) {}''')
content = content.replace("await db.execute('ALTER TABLE payments ADD COLUMN loan_sync_id TEXT');", '''try {
        await db.execute('ALTER TABLE payments ADD COLUMN loan_sync_id TEXT');
      } catch (e) {}''')

with open(db_path, 'w', encoding='utf-8') as f:
    f.write(content)

print('DBHelper idempotency added.')
