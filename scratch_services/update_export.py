import os
import re

path = r'd:\vscode\credit\scratch_services\excel_export_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Add sync_id to export headers and rows
# Usually there is a list of headers like: ['id', 'borrower_code', ...]
# We need to inject 'sync_id' right after 'id'
# Let's just do a regex replace for the header lists

# For borrowers
content = content.replace(
    "['id', 'borrower_code',",
    "['id', 'sync_id', 'borrower_code',"
)
content = content.replace(
    "b['id'], b['borrower_code'],",
    "b['id'], b['sync_id'], b['borrower_code'],"
)

# For loans
content = content.replace(
    "['id', 'borrower_id', 'loan_amount',",
    "['id', 'sync_id', 'borrower_sync_id', 'borrower_id', 'loan_amount',"
)
content = content.replace(
    "l['id'], l['borrower_id'], l['loan_amount'],",
    "l['id'], l['sync_id'], l['borrower_sync_id'], l['borrower_id'], l['loan_amount'],"
)

# For payments
content = content.replace(
    "['id', 'loan_id', 'amount',",
    "['id', 'sync_id', 'loan_sync_id', 'loan_id', 'amount',"
)
content = content.replace(
    "p['id'], p['loan_id'], p['amount'],",
    "p['id'], p['sync_id'], p['loan_sync_id'], p['loan_id'], p['amount'],"
)

# For expenses
content = content.replace(
    "['id', 'amount', 'expense_date',",
    "['id', 'sync_id', 'amount', 'expense_date',"
)
content = content.replace(
    "e['id'], e['amount'], e['expense_date'],",
    "e['id'], e['sync_id'], e['amount'], e['expense_date'],"
)

# For investments
content = content.replace(
    "['id', 'amount', 'inv_date',",
    "['id', 'sync_id', 'amount', 'inv_date',"
)
content = content.replace(
    "i['id'], i['amount'], i['inv_date'],",
    "i['id'], i['sync_id'], i['amount'], i['inv_date'],"
)

# For service_costs
content = content.replace(
    "['id', 'amount', 'description',",
    "['id', 'sync_id', 'amount', 'description',"
)
content = content.replace(
    "s['id'], s['amount'], s['description'],",
    "s['id'], s['sync_id'], s['amount'], s['description'],"
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Export service updated.')
