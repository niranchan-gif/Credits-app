import os
import urllib.request
import shutil

fonts_dir = r"d:\vscode\credit\assets\fonts"
os.makedirs(fonts_dir, exist_ok=True)

urls = {
    "Roboto-Regular.ttf": "https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Regular.ttf",
    "Roboto-Bold.ttf": "https://github.com/googlefonts/roboto/raw/main/src/hinted/Roboto-Bold.ttf"
}

for filename, url in urls.items():
    filepath = os.path.join(fonts_dir, filename)
    print(f"Downloading {filename}...")
    urllib.request.urlretrieve(url, filepath)
    print(f"Saved {filepath}")

credits_fonts_dir = r"d:\vscode\Credits-app\assets\fonts"
os.makedirs(credits_fonts_dir, exist_ok=True)

for filename in urls.keys():
    src = os.path.join(fonts_dir, filename)
    dst = os.path.join(credits_fonts_dir, filename)
    shutil.copy(src, dst)
    print(f"Copied {filename} to {dst}")
