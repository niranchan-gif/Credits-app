path = r'd:\vscode\Credits-app\pubspec.yaml'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("  assets:\n    - assets/icon/", "  assets:\n    - assets/icon/\n    - assets/fonts/")

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)
