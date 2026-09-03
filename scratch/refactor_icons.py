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

mapping = {
    'alertTriangle': 'strokeRoundedAlert01',
    'archive': 'strokeRoundedArchive',
    'arrowDown': 'strokeRoundedArrowDown01',
    'arrowDownLeft': 'strokeRoundedArrowDownLeft01',
    'arrowLeft': 'strokeRoundedArrowLeft01',
    'arrowUpRight': 'strokeRoundedArrowUpRight01',
    'barChart3': 'strokeRoundedBarChart01',
    'calendar': 'strokeRoundedCalendar01',
    'calendarCheck': 'strokeRoundedCalendarCheck01',
    'calendarRange': 'strokeRoundedCalendar01',
    'check': 'strokeRoundedCheckmarkBadge01',
    'checkCircle': 'strokeRoundedCheckmarkCircle01',
    'checkCircle2': 'strokeRoundedCheckmarkCircle02',
    'checkSquare': 'strokeRoundedCheckmarkSquare01',
    'chevronDown': 'strokeRoundedArrowDown01',
    'chevronRight': 'strokeRoundedArrowRight01',
    'chrome': 'strokeRoundedChrome',
    'clock': 'strokeRoundedClock01',
    'cloud': 'strokeRoundedCloud',
    'cloudLightning': 'strokeRoundedCloudLightning',
    'cloudOff': 'strokeRoundedCloudOff',
    'coins': 'strokeRoundedCoins01',
    'copy': 'strokeRoundedCopy01',
    'creditCard': 'strokeRoundedCreditCard',
    'download': 'strokeRoundedDownload01',
    'downloadCloud': 'strokeRoundedCloudDownload',
    'edit': 'strokeRoundedEdit01',
    'fileSpreadsheet': 'strokeRoundedDocumentAttachment',
    'fileText': 'strokeRoundedDocumentText',
    'fingerprint': 'strokeRoundedFingerprint',
    'flaskConical': 'strokeRoundedFlask',
    'hash': 'strokeRoundedHashtag',
    'history': 'strokeRoundedClock02',
    'home': 'strokeRoundedHome01',
    'indianRupee': 'strokeRoundedCurrencyRupee',
    'key': 'strokeRoundedKey01',
    'lock': 'strokeRoundedLock01',
    'logIn': 'strokeRoundedLogin01',
    'logOut': 'strokeRoundedLogout01',
    'mapPin': 'strokeRoundedLocation01',
    'moon': 'strokeRoundedMoon01',
    'moreVertical': 'strokeRoundedMoreVertical',
    'phone': 'strokeRoundedCall',
    'plus': 'strokeRoundedAdd01',
    'receipt': 'strokeRoundedReceipt01',
    'refreshCcw': 'strokeRoundedRefresh',
    'refreshCw': 'strokeRoundedRefresh',
    'rocket': 'strokeRoundedRocket',
    'search': 'strokeRoundedSearch01',
    'settings': 'strokeRoundedSettings01',
    'share2': 'strokeRoundedShare01',
    'shieldCheck': 'strokeRoundedShieldTick',
    'stickyNote': 'strokeRoundedNote01',
    'text': 'strokeRoundedText',
    'timer': 'strokeRoundedTimer01',
    'trash2': 'strokeRoundedDelete01',
    'trendingUp': 'strokeRoundedTrendingUp01',
    'uploadCloud': 'strokeRoundedCloudUpload',
    'user': 'strokeRoundedUser',
    'userCheck': 'strokeRoundedUserCheck01',
    'userPlus': 'strokeRoundedUserAdd01',
    'userX': 'strokeRoundedUserRemove01',
    'users': 'strokeRoundedUserGroup',
    'wallet': 'strokeRoundedWallet01',
    'wifiOff': 'strokeRoundedWifiDisconnected01',
    'wrench': 'strokeRoundedWrench01',
    'x': 'strokeRoundedCancel01',
    'xCircle': 'strokeRoundedCancelCircle',
    'zap': 'strokeRoundedFlash'
}

import difflib

# sanitize mapping to ensure they exist
for k, v in mapping.items():
    if v not in huge_icons:
        # fallback
        best = difflib.get_close_matches(v, list(huge_icons), n=1, cutoff=0.3)
        if best:
            mapping[k] = best[0]
        else:
            mapping[k] = 'strokeRoundedHelpCircle'

# Iterate through lib directory and replace
for root, _, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            filepath = os.path.join(root, f)
            with open(filepath, 'r', encoding='utf-8') as file:
                content = file.read()
            
            if 'lucide_icons' in content:
                # 1. Replace import
                content = content.replace("import 'package:lucide_icons/lucide_icons.dart';", "import 'package:hugeicons/hugeicons.dart';")
                
                # 2. Replace Icon(LucideIcons.x) -> HugeIcon(icon: HugeIcons.strokeRoundedX)
                # Need to handle standard usages.
                # First, extract all LucideIcons.* occurrences
                
                def replace_icon(m):
                    icon_name = m.group(1)
                    mapped = mapping.get(icon_name, 'strokeRoundedHelpCircle')
                    return f"HugeIcons.{mapped}"
                
                # Replace the LucideIcons.xxx part
                content = re.sub(r'LucideIcons\.([a-zA-Z0-9_]+)', replace_icon, content)
                
                # Replace Icon(HugeIcons.xxx, ...) with HugeIcon(icon: HugeIcons.xxx, ...)
                # This is tricky because Icon takes positional argument.
                # We can do this with regex carefully:
                # find "Icon(\s*HugeIcons\." -> "HugeIcon(\s*icon: HugeIcons."
                content = re.sub(r'Icon\(\s*(HugeIcons\.[a-zA-Z0-9_]+)', r'HugeIcon(icon: \1', content)
                
                with open(filepath, 'w', encoding='utf-8') as file:
                    file.write(content)
                print(f"Updated {f}")

print("Done refactoring icons.")
