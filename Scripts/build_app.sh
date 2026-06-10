#!/usr/bin/env bash
# Builds a Release PomoLight.app and a zip for Gumroad distribution.
#
#   ./Scripts/build_app.sh
#
# Produces:
#   dist/PomoLight.app   — the app (ad-hoc signed; runs locally)
#   dist/PomoLight.zip   — zipped app for upload
#
# NOTE: For a clean public release (no Gatekeeper warning), you need an Apple
# Developer account ($99/yr) to Developer-ID-sign + notarize. See Scripts/notarize.sh
# and the README. Ad-hoc signing here is enough to run and test locally.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▸ Regenerating Xcode project…"
xcodegen generate >/dev/null

echo "▸ Building Release…"
xcodebuild \
  -project PomoLight.xcodeproj \
  -scheme PomoLight \
  -configuration Release \
  -derivedDataPath ./build-release \
  clean build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" || true

APP="build-release/Build/Products/Release/PomoLight.app"
if [ ! -d "$APP" ]; then
  echo "✗ Build failed — $APP not found"; exit 1
fi

mkdir -p dist
rm -rf dist/PomoLight.app
cp -R "$APP" dist/PomoLight.app

echo "▸ Ad-hoc signing…"
codesign --force --deep --sign - dist/PomoLight.app

echo "▸ Zipping…"
( cd dist && rm -f PomoLight.zip && ditto -c -k --keepParent PomoLight.app PomoLight.zip )

echo "✅ Done:"
echo "   dist/PomoLight.app"
echo "   dist/PomoLight.zip"
