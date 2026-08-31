import os
import re

path = r'd:\vscode\credit\scratch_services\excel_backup_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add uuid import if missing
if "import 'package:uuid/uuid.dart';" not in content:
    content = "import 'package:uuid/uuid.dart';\n" + content

# 1. Borrowers
b_search = r'''          final sanitized = _sanitizeMap\(map, \[
            'borrower_code', 'name', 'phone', 'address', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted', 'is_dummy'
          \]\);
          
          // Duplicate detection via created_at or borrower_code
          if \(merge\) \{
            final existing = await txn.query\('borrowers', where: 'created_at = \? OR borrower_code = \?', whereArgs: \[sanitized\['created_at'\], sanitized\['borrower_code'\]\]\);
            if \(existing.isNotEmpty\) \{
              final exId = existing.first\['id'\] as int;
              borrowerIdMap\[oldId\] = exId;
              await txn.update\('borrowers', sanitized, where: 'id = \?', whereArgs: \[exId\]\);
            \} else \{
              final newId = await txn.insert\('borrowers', sanitized\);
              borrowerIdMap\[oldId\] = newId;
            \}
          \} else \{'''

b_replace = r'''          final oldSyncId = map['sync_id']?.toString() ?? '';
          final sanitized = _sanitizeMap(map, [
            'sync_id', 'borrower_code', 'name', 'phone', 'address', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted', 'is_dummy'
          ]);
          
          if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
            sanitized['sync_id'] = const Uuid().v4();
          }

          // Duplicate detection via sync_id or fallback
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
              sanitized['sync_id'] = existing.first['sync_id'];

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

# 2. Loans
l_search = r'''          final sanitized = _sanitizeMap\(map, \[
            'borrower_id', 'loan_amount', 'interest_amount', 'loan_date',
            'installment_days', 'end_date', 'status', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          \]\);

          sanitized\['borrower_id'\] = borrowerIdMap\[oldBorrowerId\] \?\? int.tryParse\(oldBorrowerId\);
          if \(sanitized\['borrower_id'\] == null\) continue; // Orphaned

          if \(sanitized\['loan_date'\] != null\) \{
            sanitized\['end_date'\] = DateParser.safeParse\(sanitized\['end_date'\]\).toIso8601String\(\).replaceAll\('T', ' '\);
          \}

          // Duplicate detection via borrower_id \+ loan_date \+ loan_amount
          if \(merge\) \{
            final existing = await txn.query\('loans', 
              where: 'borrower_id = \? AND loan_date = \? AND loan_amount = \?', 
              whereArgs: \[sanitized\['borrower_id'\], sanitized\['loan_date'\], sanitized\['loan_amount'\]\]
            \);
            if \(existing.isNotEmpty\) \{
              final exId = existing.first\['id'\] as int;
              loanIdMap\[oldId\] = exId;
              await txn.update\('loans', sanitized, where: 'id = \?', whereArgs: \[exId\]\);
            \} else \{
              final newId = await txn.insert\('loans', sanitized\);
              loanIdMap\[oldId\] = newId;
            \}
          \} else \{'''

l_replace = r'''          final oldSyncId = map['sync_id']?.toString() ?? '';
          final sanitized = _sanitizeMap(map, [
            'sync_id', 'borrower_sync_id', 'borrower_id', 'loan_amount', 'interest_amount', 'loan_date',
            'installment_days', 'end_date', 'status', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);
          
          if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
            sanitized['sync_id'] = const Uuid().v4();
          }

          sanitized['borrower_id'] = borrowerIdMap[oldBorrowerId] ?? int.tryParse(oldBorrowerId);
          if (sanitized['borrower_id'] == null) continue; // Orphaned
          
          if (sanitized['borrower_sync_id'] == null || sanitized['borrower_sync_id'].toString().isEmpty) {
            final b = await txn.query('borrowers', where: 'id = ?', whereArgs: [sanitized['borrower_id']]);
            if (b.isNotEmpty) sanitized['borrower_sync_id'] = b.first['sync_id'];
          }

          if (sanitized['loan_date'] != null) {
            sanitized['end_date'] = DateParser.safeParse(sanitized['end_date']).toIso8601String().replaceAll('T', ' ');
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

# 3. Payments
p_search = r'''          final sanitized = _sanitizeMap\(map, \[
            'loan_id', 'amount', 'payment_date', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          \]\);

          sanitized\['loan_id'\] = loanIdMap\[oldLoanId\] \?\? int.tryParse\(oldLoanId\);
          if \(sanitized\['loan_id'\] == null\) continue;

          if \(sanitized\['payment_date'\] != null\) \{
            sanitized\['payment_date'\] = DateParser.safeParse\(sanitized\['payment_date'\]\).toIso8601String\(\).replaceAll\('T', ' '\);
          \}

          // Duplicate detection via loan_id \+ payment_date \+ amount
          if \(merge\) \{
            final existing = await txn.query\('payments', 
              where: 'loan_id = \? AND payment_date = \? AND amount = \?', 
              whereArgs: \[sanitized\['loan_id'\], sanitized\['payment_date'\], sanitized\['amount'\]\]
            \);
            if \(existing.isNotEmpty\) \{
              await txn.update\('payments', sanitized, where: 'id = \?', whereArgs: \[existing.first\['id'\]\]\);
            \} else \{
              await txn.insert\('payments', sanitized\);
            \}
          \} else \{'''

p_replace = r'''          final oldSyncId = map['sync_id']?.toString() ?? '';
          final sanitized = _sanitizeMap(map, [
            'sync_id', 'loan_sync_id', 'loan_id', 'amount', 'payment_date', 'notes',
            'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
          ]);
          
          if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
            sanitized['sync_id'] = const Uuid().v4();
          }

          sanitized['loan_id'] = loanIdMap[oldLoanId] ?? int.tryParse(oldLoanId);
          if (sanitized['loan_id'] == null) continue;
          
          if (sanitized['loan_sync_id'] == null || sanitized['loan_sync_id'].toString().isEmpty) {
            final l = await txn.query('loans', where: 'id = ?', whereArgs: [sanitized['loan_id']]);
            if (l.isNotEmpty) sanitized['loan_sync_id'] = l.first['sync_id'];
          }

          if (sanitized['payment_date'] != null) {
            sanitized['payment_date'] = DateParser.safeParse(sanitized['payment_date']).toIso8601String().replaceAll('T', ' ');
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

# 4. Expenses
e_search = r'''            final sanitized = _sanitizeMap\(map, \[
              'amount', 'expense_date', 'category', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            \]\);

            if \(sanitized\['expense_date'\] != null\) \{
              sanitized\['expense_date'\] = DateParser.safeParse\(sanitized\['expense_date'\]\).toIso8601String\(\).replaceAll\('T', ' '\);
            \}

            if \(merge\) \{
              final existing = await txn.query\('expenses', 
                where: 'created_at = \?', 
                whereArgs: \[sanitized\['created_at'\]\]
              \);
              if \(existing.isNotEmpty\) \{
                await txn.update\('expenses', sanitized, where: 'id = \?', whereArgs: \[existing.first\['id'\]\]\);
              \} else \{
                await txn.insert\('expenses', sanitized\);
              \}
            \} else \{'''

e_replace = r'''            final oldSyncId = map['sync_id']?.toString() ?? '';
            final sanitized = _sanitizeMap(map, [
              'sync_id', 'amount', 'expense_date', 'category', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            ]);
            
            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
              sanitized['sync_id'] = const Uuid().v4();
            }

            if (sanitized['expense_date'] != null) {
              sanitized['expense_date'] = DateParser.safeParse(sanitized['expense_date']).toIso8601String().replaceAll('T', ' ');
            }

            if (merge) {
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

# 5. Investments
i_search = r'''            final sanitized = _sanitizeMap\(map, \[
              'amount', 'inv_date', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            \]\);

            if \(sanitized\['inv_date'\] != null\) \{
              sanitized\['inv_date'\] = DateParser.safeParse\(sanitized\['inv_date'\]\).toIso8601String\(\).replaceAll\('T', ' '\);
            \}

            if \(merge\) \{
              final existing = await txn.query\('investments', 
                where: 'created_at = \?', 
                whereArgs: \[sanitized\['created_at'\]\]
              \);
              if \(existing.isNotEmpty\) \{
                await txn.update\('investments', sanitized, where: 'id = \?', whereArgs: \[existing.first\['id'\]\]\);
              \} else \{
                await txn.insert\('investments', sanitized\);
              \}
            \} else \{'''

i_replace = r'''            final oldSyncId = map['sync_id']?.toString() ?? '';
            final sanitized = _sanitizeMap(map, [
              'sync_id', 'amount', 'inv_date', 'notes',
              'updated_at', 'created_at', 'last_modified_device', 'is_deleted'
            ]);
            
            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
              sanitized['sync_id'] = const Uuid().v4();
            }

            if (sanitized['inv_date'] != null) {
              sanitized['inv_date'] = DateParser.safeParse(sanitized['inv_date']).toIso8601String().replaceAll('T', ' ');
            }

            if (merge) {
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

# 6. Service Costs
s_search = r'''            final sanitized = _sanitizeMap\(map, \[
              'amount', 'description', 'dateCreated', 'createdBy', 'timestamp', 'is_deleted'
            \]\);

            // Duplicate detection
            if \(merge\) \{
              final existing = await txn.query\('service_costs', 
                where: 'timestamp = \?', 
                whereArgs: \[sanitized\['timestamp'\]\]
              \);
              if \(existing.isNotEmpty\) \{
                await txn.update\('service_costs', sanitized, where: 'id = \?', whereArgs: \[existing.first\['id'\]\]\);
              \} else \{
                await txn.insert\('service_costs', sanitized\);
              \}
            \} else \{'''

s_replace = r'''            final oldSyncId = map['sync_id']?.toString() ?? '';
            final sanitized = _sanitizeMap(map, [
              'sync_id', 'amount', 'description', 'dateCreated', 'createdBy', 'timestamp', 'is_deleted'
            ]);
            
            if (sanitized['sync_id'] == null || sanitized['sync_id'].toString().isEmpty) {
              sanitized['sync_id'] = const Uuid().v4();
            }

            // Duplicate detection
            if (merge) {
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

content = re.sub(b_search, b_replace, content)
content = re.sub(l_search, l_replace, content)
content = re.sub(p_search, p_replace, content)
content = re.sub(e_search, e_replace, content)
content = re.sub(i_search, i_replace, content)
content = re.sub(s_search, s_replace, content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Backup service rewritten cleanly.')
