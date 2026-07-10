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

# Keys added AFTER the original workflow ran, hand-translated (2026-07: VoiceOver
# remaining-time phrase; widget bell-slash badge). Merged so re-assembling from
# the old workflow JSON never drops them. A future workflow that includes these
# keys wins over this table.
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
    "Notifications off": {
        "cs": "Oznámení vypnuta", "da": "Notifikationer er slået fra",
        "de": "Mitteilungen aus", "el": "Ειδοποιήσεις ανενεργές",
        "es": "Notificaciones desactivadas", "fi": "Ilmoitukset pois käytöstä",
        "fil": "Naka-off ang mga notification", "fr": "Notifications désactivées",
        "hu": "Értesítések kikapcsolva", "id": "Notifikasi nonaktif",
        "it": "Notifiche disattivate", "ja": "通知オフ", "ko": "알림 꺼짐",
        "ms": "Pemberitahuan dimatikan", "nb": "Varsler av", "nl": "Meldingen uit",
        "pl": "Powiadomienia wyłączone", "pt-BR": "Notificações desativadas",
        "pt-PT": "Notificações desativadas", "ro": "Notificări dezactivate",
        "ru": "Уведомления выключены", "sv": "Notiser av",
        "th": "การแจ้งเตือนปิดอยู่", "tr": "Bildirimler kapalı",
        "uk": "Сповіщення вимкнено", "vi": "Đã tắt thông báo",
        "zh-Hans": "通知已关闭", "zh-Hant": "通知已關閉",
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
    all_keys = list(keys) + [k for k in MANUAL if k not in keys]
    for k in all_keys:
        v = trans.get(k)
        if not v or not str(v).strip():
            v = MANUAL.get(k, {}).get(code)
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
