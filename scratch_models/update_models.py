import os
import re

models_dir = r'd:\vscode\credit\scratch_models'

models_map = {
    'borrower.dart': {'class': 'Borrower', 'has_rel': False, 'rel_name': ''},
    'loan.dart': {'class': 'Loan', 'has_rel': True, 'rel_name': 'borrowerSyncId'},
    'payment.dart': {'class': 'Payment', 'has_rel': True, 'rel_name': 'loanSyncId'},
    'expense.dart': {'class': 'Expense', 'has_rel': False, 'rel_name': ''},
    'investment.dart': {'class': 'Investment', 'has_rel': False, 'rel_name': ''},
    'service_cost.dart': {'class': 'ServiceCost', 'has_rel': False, 'rel_name': ''},
}

for file_name, meta in models_map.items():
    file_path = os.path.join(models_dir, file_name)
    if not os.path.exists(file_path):
        continue
    
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()

    class_name = meta['class']
    has_rel = meta['has_rel']
    rel_name = meta['rel_name']

    # 1. Add fields to class definition
    if 'String syncId;' not in content:
        # Find 'int? id;' and insert after
        if has_rel:
            content = re.sub(
                r'(int\??\s+id;)',
                r'\1\n  String syncId;\n  String? ' + rel_name + ';',
                content, count=1
            )
        else:
            content = re.sub(
                r'(int\??\s+id;)',
                r'\1\n  String syncId;',
                content, count=1
            )
    
    # 2. Add to constructor
    if 'this.syncId = \'\'' not in content:
        # Find constructor block
        if has_rel:
            content = re.sub(
                rf'({class_name}\(\{{)',
                rf'\1\n    this.syncId = \'\',\n    this.{rel_name},',
                content, count=1
            )
        else:
            content = re.sub(
                rf'({class_name}\(\{{)',
                rf'\1\n    this.syncId = \'\',',
                content, count=1
            )

    # 3. Add to fromMap
    if 'sync_id' not in content:
        if has_rel:
            content = re.sub(
                r'(id:\s*map\[\'id\'\],)',
                rf"\1\n      syncId: map['sync_id']?.toString() ?? '',\n      {rel_name}: map['{re.sub(r'(?<!^)(?=[A-Z])', '_', rel_name).lower()}']?.toString(),",
                content, count=1
            )
        else:
            content = re.sub(
                r'(id:\s*map\[\'id\'\],)',
                r"\1\n      syncId: map['sync_id']?.toString() ?? '',",
                content, count=1
            )

    # 4. Add to toMap
    if "'sync_id': syncId" not in content:
        if has_rel:
            content = re.sub(
                r'(if \(id != null\) \'id\': id,)',
                rf"\1\n      'sync_id': syncId,\n      '{re.sub(r'(?<!^)(?=[A-Z])', '_', rel_name).lower()}': {rel_name},",
                content, count=1
            )
        else:
            content = re.sub(
                r'(if \(id != null\) \'id\': id,)',
                r"\1\n      'sync_id': syncId,",
                content, count=1
            )
    
    with open(file_path, 'w', encoding='utf-8') as f:
        f.write(content)

print('Models updated.')
