import os
import re

lib_dir = r"d:\vscode\credit\lib"
hugeicons_file = r"C:\Users\gpk00\AppData\Local\Pub\Cache\hosted\pub.dev\hugeicons-1.1.7\lib\hugeicons.dart"

huge_icons = set()
with open(hugeicons_file, 'r', encoding='utf-8') as f:
    for line in f:
        match = re.search(r"static const .* (strokeRounded[a-zA-Z0-9_]+) =", line)
        if match:
            huge_icons.add(match.group(1))

lucide_icons = [
"alertTriangle", "archive", "arrowDown", "arrowDownLeft", "arrowLeft", "arrowUpRight", "barChart3", "calendar", "calendarCheck", "calendarRange", "check", "checkCircle", "checkCircle2", "checkSquare", "chevronDown", "chevronRight", "chrome", "clock", "cloud", "cloudLightning", "cloudOff", "coins", "copy", "creditCard", "download", "downloadCloud", "edit", "fileSpreadsheet", "fileText", "fingerprint", "flaskConical", "hash", "history", "home", "indianRupee", "key", "lock", "logIn", "logOut", "mapPin", "moon", "moreVertical", "phone", "plus", "receipt", "refreshCcw", "refreshCw", "rocket", "search", "settings", "share2", "shieldCheck", "stickyNote", "text", "timer", "trash2", "trendingUp", "uploadCloud", "user", "userCheck", "userPlus", "userX", "users", "wallet", "wifiOff", "wrench", "x", "xCircle", "zap"
]

import difflib

mapping = {}
for l_icon in lucide_icons:
    # try to find a match
    # e.g., 'home' -> 'strokeRoundedHome01'
    # we can use difflib to find the closest match in huge_icons after stripping 'strokeRounded'
    best_match = difflib.get_close_matches("strokeRounded" + l_icon[0].upper() + l_icon[1:], list(huge_icons), n=1, cutoff=0.4)
    if best_match:
        mapping[l_icon] = best_match[0]
    else:
        # fallback
        mapping[l_icon] = "strokeRoundedHelp" 
        
print("Mapping:")
for k, v in mapping.items():
    print(f"'{k}': '{v}',")
