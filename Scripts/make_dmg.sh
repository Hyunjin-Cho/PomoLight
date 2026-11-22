#!/usr/bin/env bash
# Builds dist/PomoLight.dmg — the drag-to-Applications install window people see when they open the
# download — then signs, notarizes and staples the DMG itself.
# 2026-11-20 (#73): for the GitHub release (it used to say "for Gumroad" — never used).
# 2026-11-22 (#11): was a bare window with the app and an Applications link. Now it has a background
#   (Scripts/dmg/background.swift), fixed icon positions and window size (Scripts/dmg/settings.py),
#   the version in the volume name, and the DMG is signed and notarized too — before, only the app
#   inside was, so the DMG itself reached people unverified. Same shape as ddaka's install window.
#
# Run Scripts/build_app.sh first; Scripts/notarize.sh calls this after stapling the app, so the app
# in the DMG is the stapled one.
#
# ONE-TIME setup — dmgbuild lives in a project venv (.tools/ is not committed):
#   python3 -m venv .tools/venv && .tools/venv/bin/python -m pip install "dmgbuild>=1.6.7"
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/PomoLight.app"
DMG="dist/PomoLight.dmg"
PROFILE="${NOTARY_PROFILE:-pomolight-notary}"
TEAM="6RH6FXY82P"
DMGBUILD_PY=".tools/venv/bin/python"
# 🔒 1.6.7 or newer: older dmgbuild writes a .DS_Store blob that macOS 26.2+ refuses, and the DMG opens
#    with NO background — the build still succeeds, so nothing else would catch it (FB21405103).
DMGBUILD_MIN="1.6.7"

[ -d "$APP" ] || { echo "✗ $APP missing — run Scripts/build_app.sh first"; exit 1; }
[ -x "$DMGBUILD_PY" ] || { echo "✗ dmgbuild not set up — run once:"; echo "  python3 -m venv .tools/venv && .tools/venv/bin/python -m pip install \"dmgbuild>=$DMGBUILD_MIN\""; exit 1; }
DMGBUILD_VERSION=$("$DMGBUILD_PY" -c 'import dmgbuild; print(dmgbuild.__version__)')
"$DMGBUILD_PY" - "$DMGBUILD_VERSION" "$DMGBUILD_MIN" <<'PY' || { echo "✗ dmgbuild $DMGBUILD_VERSION is too old (need $DMGBUILD_MIN+):"; echo "  .tools/venv/bin/python -m pip install --upgrade dmgbuild"; exit 1; }
import sys
have, need = (tuple(int(p) for p in v.split(".")[:3]) for v in sys.argv[1:3])
sys.exit(0 if have >= need else 1)
PY

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
VOLUME="PomoLight $VERSION"
IDENTITY=$(security find-identity -v -p codesigning | awk -v team="($TEAM)" '/Developer ID Application/ && index($0, team) {print $2; exit}')
[ -n "$IDENTITY" ] || { echo "✗ No Developer ID Application identity for team $TEAM in the keychain"; exit 1; }

# No EXIT trap on purpose. 2026-11-22 (measured): under macOS's bash 3.2 an unbound-variable error inside a
# script with an EXIT trap exits 0 — even with `rc=$?; …; exit $rc` in the trap — so notarize.sh would
# carry on after a DMG that was never built. Without the trap the same error exits 1. The scratch folder
# lives in build/ (ignored) and is cleared at the start and on success instead.
WORK="build/dmg-work"
rm -rf "$WORK" && mkdir -p "$WORK"

echo "▸ Drawing the install window background…"
swift Scripts/dmg/background.swift "$WORK"
tiffutil -cathidpicheck "$WORK/background.png" "$WORK/background@2x.png" -out "$WORK/background.tiff" >/dev/null

echo "▸ Building \"${VOLUME}\" with dmgbuild ${DMGBUILD_VERSION}…"
rm -f "$DMG"
"$DMGBUILD_PY" -m dmgbuild -s Scripts/dmg/settings.py -D app="$APP" -D background="$WORK/background.tiff" "$VOLUME" "$DMG"

echo "▸ Signing the DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --strict --verbose=1 "$DMG"

echo "▸ Notarizing the DMG (waits for result)…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "▸ Gatekeeper check (as a downloaded DMG is checked when opened)…"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

rm -rf "$WORK"
echo "✅ $DMG — \"${VOLUME}\", signed, notarized and stapled"
