import os

paths = [
    r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart',
    r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
]

for path in paths:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    target_line = "final todayStr = DateFormat('dd-MM-yyyy').format(DateTime.now());"
    replacement = "if (balanceToPay < 0) balanceToPay = 0.0;\n                      " + target_line
    
    if 'if (balanceToPay < 0) balanceToPay = 0.0;' not in content:
        content = content.replace(target_line, replacement)

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Patched successfully on both projects')
