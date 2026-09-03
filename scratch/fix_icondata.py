import os

lib_dir = r"d:\vscode\credit\lib"

for root, _, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            filepath = os.path.join(root, f)
            with open(filepath, 'r', encoding='utf-8') as file:
                content = file.read()
            
            if 'IconData' in content:
                content = content.replace('IconData', 'dynamic')
                with open(filepath, 'w', encoding='utf-8') as file:
                    file.write(content)
                print(f"Fixed {f}")
