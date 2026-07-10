#!/usr/bin/env bash
# Builds a notarization-ready Developer ID PomoLight.app via archive + export.
#
#   ./Scripts/build_app.sh
#
# Produces:
#   dist/PomoLight.app   — Developer ID signed, hardened runtime, secure timestamp,
#                          no get-task-allow (i.e. ready to notarize)
#   dist/PomoLight.zip   — zipped app for upload
#
# A plain `xcodebuild build` signs for development (no timestamp + get-task-allow),
# which Apple's notary service REJECTS — so we archive then export with the
# developer-id method (Scripts/ExportOptions.plist). Then run Scripts/notarize.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Regenerating Xcode project…"
xcodegen generate >/dev/null

ARCHIVE="build-release/PomoLight.xcarchive"
EXPORT="build-release/export"

echo "▸ Archiving (Release)…"
rm -rf "$ARCHIVE"
xcodebuild \
  -project PomoLight.xcodeproj \
  -scheme PomoLight \
  -configuration Release \
  -derivedDataPath ./build-release \
  -archivePath "$ARCHIVE" \
  archive \
  | grep -E "error:|ARCHIVE SUCCEEDED|ARCHIVE FAILED|BUILD FAILED" || true

[ -d "$ARCHIVE" ] || { echo "✗ Archive failed — $ARCHIVE not found"; exit 1; }

echo "▸ Exporting (Developer ID)…"
rm -rf "$EXPORT"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  -exportPath "$EXPORT" \
  | grep -E "error:|EXPORT SUCCEEDED|Exported" || true

APP="$EXPORT/PomoLight.app"
[ -d "$APP" ] || { echo "✗ Export failed — $APP not found"; exit 1; }

mkdir -p dist
rm -rf dist/PomoLight.app
cp -R "$APP" dist/PomoLight.app

echo "▸ Verifying signature…"
# A bad signature must NOT produce a "ready to ship" ZIP — fail loudly here
# instead of letting Gatekeeper reject the app on a user's Mac.
codesign --verify --strict --verbose=1 dist/PomoLight.app \
  || { echo "✗ Signature verification FAILED — not packaging"; exit 1; }
SIGN_INFO=$(codesign -dv --verbose=2 dist/PomoLight.app 2>&1)
echo "$SIGN_INFO" | grep -E "Authority=Developer ID|TeamIdentifier|Timestamp|flags" || true
echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application" \
  || { echo "✗ Not signed with a Developer ID Application identity"; exit 1; }
echo "$SIGN_INFO" | grep -q "TeamIdentifier=6RH6FXY82P" \
  || { echo "✗ Unexpected TeamIdentifier (want 6RH6FXY82P)"; exit 1; }

echo "▸ Zipping…"
( cd dist && rm -f PomoLight.zip && ditto -c -k --keepParent PomoLight.app PomoLight.zip )

echo "✅ Done:"
echo "   dist/PomoLight.app   (Developer ID signed, notarization-ready)"
echo "   dist/PomoLight.zip"
echo "   → Next: Scripts/notarize.sh"
