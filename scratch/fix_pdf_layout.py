import os
import re

path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix S.No calculation
content = content.replace(
    'static Widget _buildPaymentTable(List<Map<String, dynamic>> payments, int globalOffset) {',
    'static Widget _buildPaymentTable(List<Map<String, dynamic>> payments, int globalOffset, int totalPayments) {'
)
content = content.replace(
    '_buildPaymentTable(pagePayments, globalPaymentOffset),',
    '_buildPaymentTable(pagePayments, globalPaymentOffset, borrower.payments?.length ?? (globalOffset + pagePayments.length)),'
)

# Replace sNo calculation to be descending (total - offset - i)
# Wait, actually we can just pass totalPayments from the top. 
content = content.replace(
    'final sNo = globalOffset + i + 1;',
    'final sNo = totalPayments - (globalOffset + i);'
)

# Reduce paddings and font sizes
content = content.replace('padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30)', 'padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)')
content = content.replace('fontSize: 28', 'fontSize: 22') # Payment History
content = content.replace('SizedBox(height: 30)', 'SizedBox(height: 16)')
content = content.replace('SizedBox(height: 16)', 'SizedBox(height: 8)')

# Header
content = content.replace('padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 25)', 'padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)')
content = content.replace('fontSize: 32', 'fontSize: 24') # STATEMENT
content = content.replace('fontSize: 18', 'fontSize: 14') # Tamil text, Page text
content = content.replace('fontSize: 22', 'fontSize: 16') # Date, cell text
content = content.replace('width: 60,\n                height: 60', 'width: 45,\n                height: 45')
content = content.replace('size: 35', 'size: 24') # Icon

# Small header
content = content.replace('padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20)', 'padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12)')
content = content.replace('fontSize: 24', 'fontSize: 18') # Statement name
content = content.replace('fontSize: 20', 'fontSize: 14') # Page 2 of X

# Borrower Details
content = content.replace('padding: const EdgeInsets.all(30)', 'padding: const EdgeInsets.all(20)')
content = content.replace('fontSize: 38', 'fontSize: 26') # Name
content = content.replace('fontSize: 22', 'fontSize: 16') # Phone/Address
content = content.replace('fontSize: 28', 'fontSize: 20') # Code

# Paid/Balance boxes
content = content.replace('padding: const EdgeInsets.all(20)', 'padding: const EdgeInsets.all(12)')
content = content.replace('fontSize: 32', 'fontSize: 22') # Amounts

# Table
content = content.replace('padding: const EdgeInsets.all(40)', 'padding: const EdgeInsets.all(20)')
content = content.replace('padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24)', 'padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16)')
content = content.replace('fontSize: isHeader ? 22 : 24', 'fontSize: isHeader ? 16 : 14')

# Fix alignment of S.No - it says "misalligned", maybe S.No should be centered?
content = content.replace("_cell('$sNo', flex: 1)", "_cell('$sNo', flex: 1, align: Alignment.center)")
content = content.replace("_cell('வ.எண்', isHeader: true, flex: 1)", "_cell('வ.எண்', isHeader: true, flex: 1, align: Alignment.center)")

# Update payments per page to be higher since we reduced sizes
content = content.replace('static const int _paymentsPerPageFirst = 15;', 'static const int _paymentsPerPageFirst = 18;')
content = content.replace('static const int _paymentsPerPageNext = 22;', 'static const int _paymentsPerPageNext = 28;')


with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
