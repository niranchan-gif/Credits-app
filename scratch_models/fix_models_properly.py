import os
import glob
import re

models_dir = r'd:\vscode\credit\scratch_models'

for path in glob.glob(os.path.join(models_dir, '*.dart')):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # 1. Import uuid
    if 'import \'package:uuid/uuid.dart\';' not in content:
        content = 'import \'package:uuid/uuid.dart\';\n' + content

    # 2. Fix this.syncId = \'\', or this.syncId = '',
    content = re.sub(r"this\.syncId = \\'\\',", "String? syncId,", content)
    content = re.sub(r"this\.syncId = '',", "String? syncId,", content)

    # 3. Add initializer list to constructor
    # Find constructor signature end
    # E.g. Borrower({ ... })
    # We want Borrower({ ... }) : syncId = syncId ?? const Uuid().v4();
    class_name = os.path.basename(path).split('.')[0].title().replace('_', '')
    if class_name == 'ServiceCost':
        class_name = 'ServiceCost'
    
    # We look for }) { or });
    # Replace it with }) : syncId = syncId ?? const Uuid().v4() {
    # or }) : syncId = syncId ?? const Uuid().v4();
    content = re.sub(r"(\}\))(\s*\{)", r"\1 : syncId = syncId ?? const Uuid().v4()\2", content, count=1)
    content = re.sub(r"(\}\))(\s*;)", r"\1 : syncId = syncId ?? const Uuid().v4()\2", content, count=1)
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Models fully fixed.')
