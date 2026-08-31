path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

if '?' in content:
    import re
    # find lines with multiple ? marks
    for i, line in enumerate(content.split('\n')):
        if line.count('?') > 2:
            print(f"Line {i+1}: {line.strip()}")
