#!/usr/bin/env bash
# Notarize + staple PomoLight for a Gatekeeper-clean GitHub release.
# 2026-11-20 (#73): releases go to GitHub (never Gumroad — that section of the README was
# stale), and the in-app updater (OnePercent) downloads `PomoLight_<version>.zip`, so the
# stapled ZIP is also written under that name.
# Run Scripts/build_app.sh first (Developer ID signed app in dist/).
#
# ONE-TIME setup — create an app-specific password at https://appleid.apple.com
# (Sign-In & Security → App-Specific Passwords), then store a notary profile.
# Pass your own Apple ID through the environment so no personal address is
# committed to this repo (2026-08-15):
#
#   export APPLE_ID="you@example.com"
#   xcrun notarytool store-credentials pomolight-notary \
#     --apple-id "$APPLE_ID" --team-id 6RH6FXY82P \
#     --password "<your-app-specific-password>"
#
# That is setup only — this script never reads APPLE_ID. Once the profile
# exists in the keychain, the credentials come from it alone.
#
# Then just run:  ./Scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PROFILE="${NOTARY_PROFILE:-pomolight-notary}"

[ -d dist/PomoLight.app ] || { echo "✗ Run Scripts/build_app.sh first"; exit 1; }

echo "▸ Zipping for submission…"
( cd dist && rm -f PomoLight-notary.zip && ditto -c -k --keepParent PomoLight.app PomoLight-notary.zip )

echo "▸ Submitting to Apple notary service (waits for result)…"
xcrun notarytool submit dist/PomoLight-notary.zip --keychain-profile "$PROFILE" --wait

echo "▸ Stapling the ticket…"
xcrun stapler staple dist/PomoLight.app
xcrun stapler validate dist/PomoLight.app

echo "▸ Repackaging stapled app…"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" dist/PomoLight.app/Contents/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" dist/PomoLight.app/Contents/Info.plist)
RELEASE_ZIP="PomoLight_${VERSION}.zip"
( cd dist && rm -f PomoLight.zip PomoLight-notary.zip "$RELEASE_ZIP" \
    && ditto -c -k --keepParent PomoLight.app PomoLight.zip \
    && ditto -c -k --keepParent PomoLight.app "$RELEASE_ZIP" )
./Scripts/make_dmg.sh

# Clean loose .app copies so Spotlight/the app launcher only ever sees the one
# in /Applications (duplicates here made the launcher list PomoLight 2-3 times).
echo "▸ Cleaning loose app copies (zip/dmg keep the distributable)…"
# 2026-11-22 (#19): unregister them from Launch Services first, as install_local.sh does. Deleting
# alone left the archive's intermediate copy
# (build-release/…/InstallationBuildProductsLocation/Applications/PomoLight.app) registered with no
# folder behind it — seen after two notarize runs. Found rather than listed: those paths are xcodebuild's.
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
{ find dist build-release -name PomoLight.app -type d -prune 2>/dev/null || true; } | while IFS= read -r p; do
  "$LSREG" -u "$PWD/$p" >/dev/null 2>&1 || true
done
rm -rf dist/PomoLight.app build-release

echo "✅ Notarized & stapled — PomoLight ${VERSION} (build ${BUILD})."
echo "   Release on GitHub: tag ${VERSION}, attach dist/${RELEASE_ZIP} (the in-app updater looks for exactly this name)"
echo "   and dist/PomoLight.dmg for people downloading by hand."
echo "   Check the ZIP first with the updater's own code (OnePercent checkout, previous release's version and build):"
echo "     swift run --package-path <OnePercent> onepercent-check --zip dist/${RELEASE_ZIP} --tag ${VERSION} \\"
echo "       --repository Hyunjin-Cho/PomoLight --team 6RH6FXY82P --bundle-id com.vismo.pomolight --app-name PomoLight \\"
echo "       --previous-version <x> --previous-build <n>"
echo "   Every release must raise CFBundleVersion (CURRENT_PROJECT_VERSION in project.yml) as well as the version."
