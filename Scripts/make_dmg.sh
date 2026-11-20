#!/usr/bin/env bash
# Wraps dist/PomoLight.app into a simple drag-to-Applications .dmg for the GitHub release (2026-11-20 #73: was "for Gumroad" — never used).
# Run build_app.sh first.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="dist/PomoLight.app"
[ -d "$APP" ] || { echo "✗ $APP missing — run Scripts/build_app.sh first"; exit 1; }

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f dist/PomoLight.dmg
hdiutil create -volname "PomoLight" -srcfolder "$STAGE" -ov -format UDZO dist/PomoLight.dmg >/dev/null
rm -rf "$STAGE"

echo "✅ dist/PomoLight.dmg"
