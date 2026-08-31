import os
import re

path = r'd:\vscode\credit\scratch_services\excel_backup_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add uuid import if missing
if "import 'package:uuid/uuid.dart';" not in content:
    content = "import 'package:uuid/uuid.dart';\n" + content

# 1. Borrowers
b_search = r'''          // Duplicate detection via created_at or borrower_code\s*if \(merge\) \{\s*final existing = await txn\.query\('borrowers', where: 'created_at = \? OR borrower_code = \?', whereArgs: \[sanitized\['created_at'\], sanitized\['borrower_code'\]\]\);\s*if \(existing\.isNotEmpty\) \{\s*final exId = existing\.first\['id'\] as int;\s*borrowerIdMap\[oldId\] = exId;\s*final localUpdatedAt = existing\.first\['updated_at'\] as int\? \?\? 0;\s*final backupUpdatedAt = sanitized\['updated_at'\] as int\? \?\? 0;\s*if \(backupUpdatedAt > localUpdatedAt\) \{\s*await txn\.update\('borrowers', sanitized, where: 'id = \?', whereArgs: \[exId\]\);\s*\}\s*\} else \{\s*final newId = await txn\.insert\('borrowers', sanitized\);\s*borrowerIdMap\[oldId\] = newId;\s*\}\s*\} else \{'''

b_replace = r'''          // Duplicate detection via sync_id or fallback
          if (merge) {
            List<Map<String, dynamic>> existing = [];
            if (oldSyncId.isNotEmpty) {
              existing = await txn.query('borrowers', where: 'sync_id = ?', whereArgs: [oldSyncId]);
            }
            if (existing.isEmpty) {
              existing = await txn.query('borrowers', where: 'created_at = ? OR borrower_code = ?', whereArgs: [sanitized['created_at'], sanitized['borrower_code']]);
            }
            if (existing.isNotEmpty) {
              final exId = existing.first['id'] as int;
              borrowerIdMap[oldId] = exId;
              
              sanitized['sync_id'] = existing.first['sync_id']; // keep local sync_id

              final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
              final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
              if (backupUpdatedAt > localUpdatedAt) {
                await txn.update('borrowers', sanitized, where: 'id = ?', whereArgs: [exId]);
              }
            } else {
              final newId = await txn.insert('borrowers', sanitized);
              borrowerIdMap[oldId] = newId;
            }
          } else {'''

# We need to inject oldSyncId and generation logic before sanitizeMap
# In importBackup, for each sheet we parse map.
# We'll just run a general replacement for inal sanitized = _sanitizeMap(map, [ to include the sync_id stuff.
# Borrowers
content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'borrower_code',)",
    r"final oldSyncId = map['sync_id']?.toString() ?? '';\n            final sanitized = _sanitizeMap(map, [\n              'id', 'sync_id', 'borrower_code',",
    content
)
# Inject uuid generation right after sanitized
content = re.sub(
    r"(final sanitized = _sanitizeMap[^;]+;\s*)",
    r"\1if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {\n              sanitized['sync_id'] = const Uuid().v4();\n            }\n            ",
    content, count=1 # Only first one for borrowers, we'll do others specifically
)
content = re.sub(b_search, b_replace, content)

# 2. Loans
l_search = r'''          // Duplicate detection via borrower_id \+ loan_date \+ loan_amount\s*if \(merge\) \{\s*final existing = await txn\.query\('loans', \s*where: 'borrower_id = \? AND loan_date = \? AND loan_amount = \?', \s*whereArgs: \[sanitized\['borrower_id'\], sanitized\['loan_date'\], sanitized\['loan_amount'\]\]\s*\);\s*if \(existing\.isNotEmpty\) \{\s*final exId = existing\.first\['id'\] as int;\s*loanIdMap\[oldId\] = exId;\s*final localUpdatedAt = existing\.first\['updated_at'\] as int\? \?\? 0;\s*final backupUpdatedAt = sanitized\['updated_at'\] as int\? \?\? 0;\s*if \(backupUpdatedAt > localUpdatedAt\) \{\s*await txn\.update\('loans', sanitized, where: 'id = \?', whereArgs: \[exId\]\);\s*\}\s*\} else \{\s*final newId = await txn\.insert\('loans', sanitized\);\s*loanIdMap\[oldId\] = newId;\s*\}\s*\} else \{'''

l_replace = r'''          if (sanitized['borrower_sync_id'] == null || sanitized['borrower_sync_id'].toString().isEmpty) {
            final b = await txn.query('borrowers', where: 'id = ?', whereArgs: [sanitized['borrower_id']]);
            if (b.isNotEmpty) sanitized['borrower_sync_id'] = b.first['sync_id'];
          }
          // Duplicate detection via sync_id or fallback
          if (merge) {
            List<Map<String, dynamic>> existing = [];
            if (oldSyncId.isNotEmpty) {
              existing = await txn.query('loans', where: 'sync_id = ?', whereArgs: [oldSyncId]);
            }
            if (existing.isEmpty) {
              existing = await txn.query('loans', 
                where: 'borrower_id = ? AND loan_date = ? AND loan_amount = ?', 
                whereArgs: [sanitized['borrower_id'], sanitized['loan_date'], sanitized['loan_amount']]
              );
            }
            if (existing.isNotEmpty) {
              final exId = existing.first['id'] as int;
              loanIdMap[oldId] = exId;
              
              sanitized['sync_id'] = existing.first['sync_id'];

              final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
              final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
              if (backupUpdatedAt > localUpdatedAt) {
                await txn.update('loans', sanitized, where: 'id = ?', whereArgs: [exId]);
              }
            } else {
              final newId = await txn.insert('loans', sanitized);
              loanIdMap[oldId] = newId;
            }
          } else {'''

content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'borrower_id',)",
    r"final oldSyncId = map['sync_id']?.toString() ?? '';\n            final sanitized = _sanitizeMap(map, [\n              'id', 'sync_id', 'borrower_sync_id', 'borrower_id',",
    content
)
# Find the second instance of sanitize assignment to add UUID gen
content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'sync_id',\s*'borrower_sync_id',\s*'borrower_id',.*?\]\);)",
    r"\1\n            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {\n              sanitized['sync_id'] = const Uuid().v4();\n            }",
    content, flags=re.DOTALL
)
content = re.sub(l_search, l_replace, content)

# 3. Payments
p_search = r'''          // Duplicate detection via loan_id \+ payment_date \+ amount\s*if \(merge\) \{\s*final existing = await txn\.query\('payments', \s*where: 'loan_id = \? AND payment_date = \? AND amount = \?', \s*whereArgs: \[sanitized\['loan_id'\], sanitized\['payment_date'\], sanitized\['amount'\]\]\s*\);\s*if \(existing\.isNotEmpty\) \{\s*final localUpdatedAt = existing\.first\['updated_at'\] as int\? \?\? 0;\s*final backupUpdatedAt = sanitized\['updated_at'\] as int\? \?\? 0;\s*if \(backupUpdatedAt > localUpdatedAt\) \{\s*await txn\.update\('payments', sanitized, where: 'id = \?', whereArgs: \[existing\.first\['id'\]\]\);\s*\}\s*\} else \{\s*await txn\.insert\('payments', sanitized\);\s*\}\s*\} else \{'''

p_replace = r'''          if (sanitized['loan_sync_id'] == null || sanitized['loan_sync_id'].toString().isEmpty) {
            final l = await txn.query('loans', where: 'id = ?', whereArgs: [sanitized['loan_id']]);
            if (l.isNotEmpty) sanitized['loan_sync_id'] = l.first['sync_id'];
          }
          // Duplicate detection via sync_id or fallback
          if (merge) {
            List<Map<String, dynamic>> existing = [];
            if (oldSyncId.isNotEmpty) {
              existing = await txn.query('payments', where: 'sync_id = ?', whereArgs: [oldSyncId]);
            }
            if (existing.isEmpty) {
              existing = await txn.query('payments', 
                where: 'loan_id = ? AND payment_date = ? AND amount = ?', 
                whereArgs: [sanitized['loan_id'], sanitized['payment_date'], sanitized['amount']]
              );
            }
            if (existing.isNotEmpty) {
              sanitized['sync_id'] = existing.first['sync_id'];
              final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
              final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
              if (backupUpdatedAt > localUpdatedAt) {
                await txn.update('payments', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
              }
            } else {
              await txn.insert('payments', sanitized);
            }
          } else {'''

content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'loan_id',)",
    r"final oldSyncId = map['sync_id']?.toString() ?? '';\n            final sanitized = _sanitizeMap(map, [\n              'id', 'sync_id', 'loan_sync_id', 'loan_id',",
    content
)
content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'sync_id',\s*'loan_sync_id',\s*'loan_id',.*?\]\);)",
    r"\1\n            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {\n              sanitized['sync_id'] = const Uuid().v4();\n            }",
    content, flags=re.DOTALL
)
content = re.sub(p_search, p_replace, content)


# 4. Expenses
e_search = r'''            if \(merge\) \{\s*final existing = await txn\.query\('expenses', \s*where: 'created_at = \?', \s*whereArgs: \[sanitized\['created_at'\]\]\s*\);\s*if \(existing\.isNotEmpty\) \{\s*final localUpdatedAt = existing\.first\['updated_at'\] as int\? \?\? 0;\s*final backupUpdatedAt = sanitized\['updated_at'\] as int\? \?\? 0;\s*if \(backupUpdatedAt > localUpdatedAt\) \{\s*await txn\.update\('expenses', sanitized, where: 'id = \?', whereArgs: \[existing\.first\['id'\]\]\);\s*\}\s*\} else \{\s*await txn\.insert\('expenses', sanitized\);\s*\}\s*\} else \{'''

e_replace = r'''            if (merge) {
              List<Map<String, dynamic>> existing = [];
              if (oldSyncId.isNotEmpty) {
                existing = await txn.query('expenses', where: 'sync_id = ?', whereArgs: [oldSyncId]);
              }
              if (existing.isEmpty) {
                existing = await txn.query('expenses', 
                  where: 'created_at = ?', 
                  whereArgs: [sanitized['created_at']]
                );
              }
              if (existing.isNotEmpty) {
                sanitized['sync_id'] = existing.first['sync_id'];
                final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
                final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
                if (backupUpdatedAt > localUpdatedAt) {
                  await txn.update('expenses', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
                }
              } else {
                await txn.insert('expenses', sanitized);
              }
            } else {'''

content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'amount',\s*'expense_date',)",
    r"final oldSyncId = map['sync_id']?.toString() ?? '';\n              final sanitized = _sanitizeMap(map, [\n                'id', 'sync_id', 'amount', 'expense_date',",
    content
)
content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'sync_id',\s*'amount',\s*'expense_date',.*?\]\);)",
    r"\1\n              if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {\n                sanitized['sync_id'] = const Uuid().v4();\n              }",
    content, flags=re.DOTALL
)
content = re.sub(e_search, e_replace, content)


# 5. Investments
i_search = r'''            if \(merge\) \{\s*final existing = await txn\.query\('investments', \s*where: 'created_at = \?', \s*whereArgs: \[sanitized\['created_at'\]\]\s*\);\s*if \(existing\.isNotEmpty\) \{\s*final localUpdatedAt = existing\.first\['updated_at'\] as int\? \?\? 0;\s*final backupUpdatedAt = sanitized\['updated_at'\] as int\? \?\? 0;\s*if \(backupUpdatedAt > localUpdatedAt\) \{\s*await txn\.update\('investments', sanitized, where: 'id = \?', whereArgs: \[existing\.first\['id'\]\]\);\s*\}\s*\} else \{\s*await txn\.insert\('investments', sanitized\);\s*\}\s*\} else \{'''

i_replace = r'''            if (merge) {
              List<Map<String, dynamic>> existing = [];
              if (oldSyncId.isNotEmpty) {
                existing = await txn.query('investments', where: 'sync_id = ?', whereArgs: [oldSyncId]);
              }
              if (existing.isEmpty) {
                existing = await txn.query('investments', 
                  where: 'created_at = ?', 
                  whereArgs: [sanitized['created_at']]
                );
              }
              if (existing.isNotEmpty) {
                sanitized['sync_id'] = existing.first['sync_id'];
                final localUpdatedAt = existing.first['updated_at'] as int? ?? 0;
                final backupUpdatedAt = sanitized['updated_at'] as int? ?? 0;
                if (backupUpdatedAt > localUpdatedAt) {
                  await txn.update('investments', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
                }
              } else {
                await txn.insert('investments', sanitized);
              }
            } else {'''

content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'amount',\s*'inv_date',)",
    r"final oldSyncId = map['sync_id']?.toString() ?? '';\n              final sanitized = _sanitizeMap(map, [\n                'id', 'sync_id', 'amount', 'inv_date',",
    content
)
content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'sync_id',\s*'amount',\s*'inv_date',.*?\]\);)",
    r"\1\n              if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {\n                sanitized['sync_id'] = const Uuid().v4();\n              }",
    content, flags=re.DOTALL
)
content = re.sub(i_search, i_replace, content)


# 6. Service Costs
s_search = r'''            // Duplicate detection\s*if \(merge\) \{\s*final existing = await txn\.query\('service_costs', \s*where: 'timestamp = \?', \s*whereArgs: \[sanitized\['timestamp'\]\]\s*\);\s*if \(existing\.isNotEmpty\) \{\s*final localTimestamp = existing\.first\['timestamp'\] as int\? \?\? 0;\s*final backupTimestamp = sanitized\['timestamp'\] as int\? \?\? 0;\s*if \(backupTimestamp > localTimestamp\) \{\s*await txn\.update\('service_costs', sanitized, where: 'id = \?', whereArgs: \[existing\.first\['id'\]\]\);\s*\}\s*\} else \{\s*await txn\.insert\('service_costs', sanitized\);\s*\}\s*\} else \{'''

s_replace = r'''            if (merge) {
              List<Map<String, dynamic>> existing = [];
              if (oldSyncId.isNotEmpty) {
                existing = await txn.query('service_costs', where: 'sync_id = ?', whereArgs: [oldSyncId]);
              }
              if (existing.isEmpty) {
                existing = await txn.query('service_costs', 
                  where: 'timestamp = ?', 
                  whereArgs: [sanitized['timestamp']]
                );
              }
              if (existing.isNotEmpty) {
                sanitized['sync_id'] = existing.first['sync_id'];
                final localTimestamp = existing.first['timestamp'] as int? ?? 0;
                final backupTimestamp = sanitized['timestamp'] as int? ?? 0;
                if (backupTimestamp > localTimestamp) {
                  await txn.update('service_costs', sanitized, where: 'id = ?', whereArgs: [existing.first['id']]);
                }
              } else {
                await txn.insert('service_costs', sanitized);
              }
            } else {'''

content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'amount',\s*'description',)",
    r"final oldSyncId = map['sync_id']?.toString() ?? '';\n              final sanitized = _sanitizeMap(map, [\n                'id', 'sync_id', 'amount', 'description',",
    content
)
content = re.sub(
    r"(final sanitized = _sanitizeMap\(map, \[\s*'id',\s*'sync_id',\s*'amount',\s*'description',.*?\]\);)",
    r"\1\n              if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {\n                sanitized['sync_id'] = const Uuid().v4();\n              }",
    content, flags=re.DOTALL
)
content = re.sub(s_search, s_replace, content)


with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Backup service updated.')
