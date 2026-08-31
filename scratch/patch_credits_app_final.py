import os
import re

path = r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

path_credit = r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart'
with open(path_credit, 'r', encoding='utf-8') as f:
    content_credit = f.read()

# Find the block in credit
match_credit = re.search(r'(IconButton\(\s*onPressed:\s*\(\)\s*async\s*\{\s*final messenger = ScaffoldMessenger.*?icon:\s*const\s*Icon\(LucideIcons\.share2,\s*color:\s*AppColors\.accent,\s*size:\s*20\),)', content_credit, re.DOTALL)
if not match_credit:
    print('Failed to regex match in credit')
    exit()

new_block = match_credit.group(1)

# In Credits-app, there's a tooltip:
match_old = re.search(r'(IconButton\(\s*tooltip:\s*\'Send Full Statement\',\s*onPressed:\s*\(\)\s*async\s*\{\s*final messenger = ScaffoldMessenger.*?icon:\s*const\s*Icon\(LucideIcons\.share2,\s*color:\s*AppColors\.accent,\s*size:\s*20\),)', content, re.DOTALL)
if not match_old:
    print('Failed to regex match in Credits-app')
    exit()

old_block = match_old.group(1)

# Add tooltip to new block
new_block = new_block.replace('IconButton(\n                    onPressed:', "IconButton(\n                    tooltip: 'Send Full Statement',\n                    onPressed:")

content = content.replace(old_block, new_block)

imports = [
    "import 'package:share_plus/share_plus.dart';",
    "import 'package:path_provider/path_provider.dart';",
    "import 'dart:io';",
    "import 'package:flutter/services.dart';",
    "import '../services/borrower_pdf_service.dart';"
]
for imp in imports:
    if imp not in content:
        content = content.replace("import 'package:flutter/material.dart';", f"import 'package:flutter/material.dart';\n{imp}")

if 'static const _whatsappChannel' not in content:
    content = content.replace('class _BorrowerLoansScreenState extends State<BorrowerLoansScreen> {', 'class _BorrowerLoansScreenState extends State<BorrowerLoansScreen> {\n  static const _whatsappChannel = MethodChannel("com.example.credit/whatsapp_share");')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print('Successfully patched Credits-app')
