import os
import re

path = r'd:\vscode\Credits-app\lib\screens\borrower_loans_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

# Since Credits-app's borrower_loans_screen.dart is back to its original state,
# I will just replace the exact share button code by searching for it via regex or exact substring.
# Let's read the exact block from d:\vscode\credit\lib\screens\borrower_loans_screen.dart
# and replace the block in Credits-app.

path_credit = r'd:\vscode\credit\lib\screens\borrower_loans_screen.dart'
with open(path_credit, 'r', encoding='utf-8') as f:
    content_credit = f.read()

start_str = 'IconButton(\n                  onPressed: () async {\n                    final messenger = ScaffoldMessenger.of(context);'
end_str = 'icon: const Icon(LucideIcons.share2, color: AppColors.accent, size: 20),'

start_idx = content_credit.find(start_str)
end_idx = content_credit.find(end_str) + len(end_str)
new_block = content_credit[start_idx:end_idx]

# Now for Credits-app:
start_str_old = "IconButton(\n                    tooltip: 'Send Full Statement',\n                    onPressed: () async {\n                      final messenger = ScaffoldMessenger.of(context);"
start_idx_old = content.find(start_str_old)
if start_idx_old == -1:
    print('Failed to find start in Credits-app')
    exit()

end_idx_old = content.find(end_str) + len(end_str)

content = content[:start_idx_old] + new_block + content[end_idx_old:]

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
print("Successfully patched Credits-app")
