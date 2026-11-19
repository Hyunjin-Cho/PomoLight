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

# Keys the old workflow JSON still carries but the app never looks up. They are
# dropped here so a re-assembly can't resurrect them (2026-08-15):
#   "Custom color" — the custom accent-color feature was removed in PR #2.
#   "Soft Chime"   — alarm-sound names are drawn with Text(verbatim:) in
#                    SettingsPanelView, so they never go through this table.
# Also gone in the same pass: the hardcoded "Glass"/"Submarine" system-sound
# names, which were never even values of AlarmSound. If sound names are ever
# localized, take "Soft Chime" back out of this set.
#   "Notifications off" (2026-08-21) — the widget's bell-slash badge. The widget
#                    went in PR #33; grep finds no lookup in Sources/, yet the
#                    string was still sitting in all 29 .lproj files and in the
#                    MANUAL table below, ready to be written back on the next
#                    re-assembly. Removed from the files in the same commit.
#   "Donate", "Support PomoLight with a donation", "Support PomoLight"
#                    (2026-11-19, #6) — the owner dropped donations; the heart and
#                    the Settings footer line went, replaced by the developer's
#                    GitHub address, which is drawn verbatim and needs no table.
#                    Removed from all 29 .lproj files in the same commit.
SKIP_KEYS = {"Custom color", "Soft Chime", "Notifications off",
             "Donate", "Support PomoLight with a donation", "Support PomoLight"}

# Keys added AFTER the original workflow ran, hand-translated (2026-07: the
# VoiceOver remaining-time phrase). Merged so re-assembling from the old workflow
# JSON never drops them. A future workflow that includes these keys wins over
# this table. 2026-08-21: the widget's "Notifications off" badge was dropped from
# here — see SKIP_KEYS above.
MANUAL = {
    "%@ remaining": {
        "cs": "Zbývá %@", "da": "%@ tilbage", "de": "Noch %@",
        "el": "Απομένουν %@", "es": "Quedan %@", "fi": "%@ jäljellä",
        "fil": "Natitirang %@", "fr": "Il reste %@", "hu": "%@ van hátra",
        "id": "Tersisa %@", "it": "Mancano %@", "ja": "残り%@",
        "ko": "%@ 남음", "ms": "Tinggal %@", "nb": "%@ igjen",
        "nl": "Nog %@", "pl": "Pozostało %@", "pt-BR": "Faltam %@",
        "pt-PT": "Faltam %@", "ro": "Au mai rămas %@", "ru": "Осталось %@",
        "sv": "%@ kvar", "th": "เหลืออีก %@", "tr": "%@ kaldı",
        "uk": "Залишилося %@", "vi": "Còn lại %@",
        "zh-Hans": "剩余%@", "zh-Hant": "剩餘%@",
    },
}

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
    all_keys = [k for k in list(keys) + [k for k in MANUAL if k not in keys]
                if k not in SKIP_KEYS]
    for k in all_keys:
        v = trans.get(k)
        if not v or not str(v).strip():
            v = MANUAL.get(k, {}).get(code)
        if not v or not str(v).strip():
            v = k          # fall back to English
            missing += 1
        lines.append(f'"{esc(k)}" = "{esc(str(v))}";')
    with open(os.path.join(lproj, "Localizable.strings"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    written.append((code, len(trans), missing))

print(f"Wrote {len(written)} localizations:")
for code, have, missing in sorted(written):
    flag = "" if missing == 0 else f"  ⚠ {missing} fell back to EN"
    print(f"  {code:8} {have} keys{flag}")
