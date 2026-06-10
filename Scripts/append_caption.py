#!/usr/bin/env python3
"""Append the localized 'rings 3 times' caption to every <lang>.lproj/Localizable.strings.
Usage: python3 Scripts/append_caption.py <workflow_output.json>"""
import json, os, sys

out_path = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res_dir = os.path.join(root, "Resources")

with open(out_path, "r", encoding="utf-8") as f:
    data = json.load(f)
result = data["result"]
source = result["source"]            # the English key
by_lang = result["map"]              # {code: translation}
by_lang["en"] = source               # base identity

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

key = esc(source)
updated = 0
for code, value in by_lang.items():
    path = os.path.join(res_dir, f"{code}.lproj", "Localizable.strings")
    if not os.path.exists(path):
        print(f"  skip {code} (no file)"); continue
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    if f'"{key}"' in content:        # already has it
        continue
    line = f'"{key}" = "{esc(str(value))}";\n'
    if not content.endswith("\n"):
        content += "\n"
    content += line
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)
    updated += 1
print(f"Appended caption to {updated} localizations.")
