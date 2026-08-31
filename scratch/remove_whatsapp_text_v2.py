import os

paths = [
    r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart',
    r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
]

for path in paths:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Empty the summaryMsg string being passed to the intent/share functions
    content = content.replace("'text': summaryMsg,", "'text': '',")
    content = content.replace("text: summaryMsg,", "text: '',")

    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Patched successfully on both projects')
