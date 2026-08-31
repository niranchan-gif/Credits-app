import os

paths = [
    r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart',
    r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
]

for path in paths:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replace webUrl
    content = content.replace("'https://web.whatsapp.com/send?phone=$digits&text=${Uri.encodeComponent(summaryMsg)}';", "'https://web.whatsapp.com/send?phone=$digits';")
    
    # Replace fallbackUri
    content = content.replace("'https://wa.me/$digits?text=${Uri.encodeComponent(summaryMsg)}');", "'https://wa.me/$digits');")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)
print('Patched successfully on both projects')
