#!/usr/bin/env python3
"""Assemble Resources/<lang>.lproj/Localizable.strings from the localization
workflow's JSON output. Missing keys fall back to the English source so nothing
is ever blank. Usage: python3 Scripts/assemble_localizations.py <workflow_output.json>"""
import json, os, sys

out_path = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res_dir = os.path.join(root, "Resources")

with open(out_path, "r", encoding="utf-8") as f:
    data = json.load(f)

result = data["result"]
keys = result["keys"]
by_lang = result["byLang"]

# Proper-noun system-sound names: identity in every language.
extra = {"Glass": "Glass", "Submarine": "Submarine"}

def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

written = []
for code, trans in by_lang.items():
    if code == "en":
        continue
    lproj = os.path.join(res_dir, f"{code}.lproj")
    os.makedirs(lproj, exist_ok=True)
    lines = [f"/* PomoLight — {code} (auto-assembled) */"]
    missing = 0
    for k in keys:
        v = trans.get(k)
        if not v or not str(v).strip():
            v = k          # fall back to English
            missing += 1
        lines.append(f'"{esc(k)}" = "{esc(str(v))}";')
    for k, v in extra.items():
        lines.append(f'"{esc(k)}" = "{esc(v)}";')
    with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    written.append((code, len(trans), missing))

print(f"Wrote {len(written)} localizations:")
for code, have, missing in sorted(written):
    flag = "" if missing == 0 else f"  ⚠ {missing} fell back to EN"
    print(f"  {code:8} {have} keys{flag}")
