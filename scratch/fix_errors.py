import os

path = r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Fix LucideIcons.copyAll -> LucideIcons.copy
content = content.replace('LucideIcons.copyAll', 'LucideIcons.copy')

# Fix balanceAmount -> (loanAmount - totalPaid)
content = content.replace('targetLoans.first.balanceAmount ?? (loanAmount - totalPaid);', '(loanAmount - totalPaid);')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
