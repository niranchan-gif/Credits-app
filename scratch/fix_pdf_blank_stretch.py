import os
import re

path = r'd:\vscode\credit\lib\services\borrower_pdf_service.dart'

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix the blank text by removing 'Roboto' font requirement.
# Replace DefaultTextStyle block
content = content.replace(
    '''          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Roboto', color: _textDark),
            child: Column(''',
    '''          child: DefaultTextStyle(
            style: const TextStyle(color: _textDark),
            child: Column('''
)

# 2. Fix the font stretching by using BoxFit.contain instead of BoxFit.fill
content = content.replace(
    'child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.fill),',
    'child: pw.Image(pw.MemoryImage(imageBytes), fit: pw.BoxFit.contain),'
)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
