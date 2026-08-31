import os
import re

path = r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

path_credit = r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart'
with open(path_credit, 'r', encoding='utf-8') as f:
    content_credit = f.read()

start_str_credit = "IconButton(\n                    onPressed: () async {\n                      final messenger = ScaffoldMessenger.of(context);"
end_str = 'icon: const Icon(LucideIcons.share2, color: AppColors.accent, size: 20),'

start_idx_credit = content_credit.find(start_str_credit)
if start_idx_credit == -1:
    print('Failed to find start in credit')
    exit()
end_idx_credit = content_credit.find(end_str, start_idx_credit) + len(end_str)
new_block = content_credit[start_idx_credit:end_idx_credit]

start_str_old = "IconButton(\n                    tooltip: 'Send Full Statement',\n                    onPressed: () async {\n                      final messenger = ScaffoldMessenger.of(context);"
start_idx_old = content.find(start_str_old)
if start_idx_old == -1:
    print('Failed to find start in Credits-app')
    exit()

end_idx_old = content.find(end_str, start_idx_old) + len(end_str)

# When replacing, add the tooltip back
new_block = new_block.replace("IconButton(\n                    onPressed: () async {", "IconButton(\n                    tooltip: 'Send Full Statement',\n                    onPressed: () async {")

content = content[:start_idx_old] + new_block + content[end_idx_old:]

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

print("Successfully patched Credits-app")
