import os

path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Increase horizontal padding to push columns closer together in the middle
content = content.replace(
    'padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),',
    'padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 100),'
)

# Increase font size from 20 to 24 for table cells
content = content.replace(
    'fontSize: 20,\n            fontWeight: isHeader ? FontWeight.bold : FontWeight.w600,',
    'fontSize: 24,\n            fontWeight: isHeader ? FontWeight.bold : FontWeight.w600,'
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
