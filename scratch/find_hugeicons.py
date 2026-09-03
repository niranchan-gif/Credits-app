import os
import re

pub_cache = os.path.expanduser("~\\AppData\\Local\\Pub\\Cache\\hosted\\pub.dev")
hugeicons_dir = None
if os.path.exists(pub_cache):
    for d in os.listdir(pub_cache):
        if d.startswith("hugeicons-"):
            hugeicons_dir = os.path.join(pub_cache, d)
            break

if not hugeicons_dir:
    print("Hugeicons package not found in cache.")
else:
    icons_file = os.path.join(hugeicons_dir, "lib", "hugeicons.dart") # might be in a subfolder or another file
    
    # Just search all dart files in the package for 'static const IconData strokeRounded'
    found_icons = []
    pattern = re.compile(r"static const IconData (strokeRounded[a-zA-Z0-9_]+)")
    for root, _, files in os.walk(hugeicons_dir):
        for f in files:
            if f.endswith(".dart"):
                with open(os.path.join(root, f), 'r', encoding='utf-8') as file:
                    content = file.read()
                    matches = pattern.findall(content)
                    found_icons.extend(matches)
    
    print(f"Found {len(found_icons)} icons.")
    # save to a file for easy lookup
    with open(r"d:\vscode\credit\scratch\hugeicons_list.txt", "w") as out:
        for i in sorted(set(found_icons)):
            out.write(i + "\n")
    print("Saved to hugeicons_list.txt")
