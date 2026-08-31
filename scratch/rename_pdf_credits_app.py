path = r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

old_str = """                      final safeCode = b.displayBorrowerCode.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
                      final filePath = '${tempDir.path}${Platform.pathSeparator}Borrower_Report_$safeCode.pdf';"""

new_str = """                      final filePath = '${tempDir.path}${Platform.pathSeparator}Report.pdf';"""

content = content.replace(old_str, new_str)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
