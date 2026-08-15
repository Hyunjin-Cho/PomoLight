#!/usr/bin/env bash
# Notarize + staple PomoLight for a Gatekeeper-clean Gumroad release.
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
( cd dist && rm -f PomoLight.zip PomoLight-notary.zip && ditto -c -k --keepParent PomoLight.app PomoLight.zip )
./Scripts/make_dmg.sh

# Clean loose .app copies so Spotlight/the app launcher only ever sees the one
# in /Applications (duplicates here made the launcher list PomoLight 2-3 times).
echo "▸ Cleaning loose app copies (zip/dmg keep the distributable)…"
rm -rf dist/PomoLight.app build-release

echo "✅ Notarized & stapled. Ship dist/PomoLight.dmg (or dist/PomoLight.zip) on Gumroad."
