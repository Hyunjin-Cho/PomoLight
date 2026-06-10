#!/usr/bin/env bash
# Builds a Release PomoLight.app (Developer ID signed) + a zip for Gumroad.
#
#   ./Scripts/build_app.sh
#
# Produces:
#   dist/PomoLight.app   — Developer ID signed, hardened runtime (ready to notarize)
#   dist/PomoLight.zip   — zipped app for upload
#
# Signing comes from project.yml (Developer ID Application, team 6RH6FXY82P). After
# this, NOTARIZE for a Gatekeeper-clean release — see Scripts/notarize.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Regenerating Xcode project…"
xcodegen generate >/dev/null

echo "▸ Building Release (Developer ID)…"
xcodebuild \
  -project PomoLight.xcodeproj \
  -scheme PomoLight \
  -configuration Release \
  -derivedDataPath ./build-release \
  clean build \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

APP="build-release/Build/Products/Release/PomoLight.app"
if [ ! -d "$APP" ]; then
  echo "✗ Build failed — $APP not found"; exit 1
fi

mkdir -p dist
rm -rf dist/PomoLight.app
cp -R "$APP" dist/PomoLight.app

echo "▸ Verifying signature…"
codesign --verify --strict --verbose=1 dist/PomoLight.app || echo "  (signature check reported issues)"
codesign -dv dist/PomoLight.app 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier" || true

echo "▸ Zipping…"
( cd dist && rm -f PomoLight.zip && ditto -c -k --keepParent PomoLight.app PomoLight.zip )

echo "✅ Done:"
echo "   dist/PomoLight.app   (Developer ID signed)"
echo "   dist/PomoLight.zip"
echo "   → Next: notarize with Scripts/notarize.sh for a Gatekeeper-clean release."
