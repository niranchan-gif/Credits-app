import os
import re

lib_dir = r"d:\vscode\credit\lib"
lucide_pattern = re.compile(r"LucideIcons\.([a-zA-Z0-9_]+)")

icons_found = set()

for root, _, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            with open(os.path.join(root, f), 'r', encoding='utf-8') as file:
                content = file.read()
                matches = lucide_pattern.findall(content)
                for m in matches:
                    icons_found.add(m)

print("Icons found:")
for i in sorted(icons_found):
    print(i)
