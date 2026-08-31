import os
import glob

for path in glob.glob(r'd:\vscode\credit\scratch_models\*.dart'):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    content = content.replace("this.syncId = \'\',", "this.syncId = '',")
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Models fixed.')
