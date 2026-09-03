import os
import re

directory = 'd:/vscode/credit/lib'
output = 'd:/vscode/credit/strings_dump.txt'

with open(output, 'w', encoding='utf-8') as out:
    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                # Regex to match Text('something') or Text("something")
                texts = re.findall(r'Text\(\s*[\'\"](.*?)[\'\"]', content)
                
                if texts:
                    out.write(f'\n--- {file} ---\n')
                    for t in texts:
                        out.write(f'{t}\n')
