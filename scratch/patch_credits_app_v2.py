import os
import re

path = r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# The block to insert (we'll fetch it from the credit project where it is already fixed and working)
path_credit = r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart'
with open(path_credit, 'r', encoding='utf-8') as f:
    content_credit = f.read()

start_str_credit = 'IconButton(\n                    onPressed: () async {\n                      final messenger = ScaffoldMessenger.of(context);'
end_str = 'icon: const Icon(LucideIcons.share2, color: AppColors.accent, size: 20),'

start_idx_credit = content_credit.find(start_str_credit)
if start_idx_credit == -1:
    print('Failed to find start in credit')
    exit()
end_idx_credit = content_credit.find(end_str, start_idx_credit) + len(end_str)
new_block = content_credit[start_idx_credit:end_idx_credit]

# Since we want to preserve the tooltip in Credits-app:
new_block = new_block.replace('IconButton(\n                    onPressed: () async {', "IconButton(\n                    tooltip: 'Send Full Statement',\n                    onPressed: () async {")

# Find the target block in Credits-app
start_str_old = "IconButton(\n                    tooltip: 'Send Full Statement',\n                    onPressed: () async {\n                      final messenger = ScaffoldMessenger.of(context);"
start_idx_old = content.find(start_str_old)
if start_idx_old == -1:
    print('Failed to find start in Credits-app')
    exit()

end_idx_old = content.find(end_str, start_idx_old) + len(end_str)

# Replace
content = content[:start_idx_old] + new_block + content[end_idx_old:]

# One final thing: Credits-app's borrower_loans_screen.dart might need imports for:
# share_plus, path_provider, pdf etc if they weren't there originally since it used to just launch WhatsApp URL.
# I'll check if they exist, if not add them.

imports = [
    "import 'package:share_plus/share_plus.dart';",
    "import 'package:path_provider/path_provider.dart';",
    "import 'dart:io';",
    "import 'package:flutter/services.dart';",
    "import '../services/borrower_pdf_service.dart';"
]
for imp in imports:
    if imp not in content:
        # Insert after material.dart
        content = content.replace("import 'package:flutter/material.dart';", f"import 'package:flutter/material.dart';\n{imp}")

# Also add whatsappChannel if it doesn't exist
if 'static const _whatsappChannel' not in content:
    content = content.replace('class _BorrowerLoansScreenState extends State<BorrowerLoansScreen> {\n    List<Loan> _loans = [];', 'class _BorrowerLoansScreenState extends State<BorrowerLoansScreen> {\n    List<Loan> _loans = [];\n    static const _whatsappChannel = MethodChannel("com.example.credit/whatsapp_share");')

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Successfully patched Credits-app")
