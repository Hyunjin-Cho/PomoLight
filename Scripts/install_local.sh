#!/usr/bin/env bash
# Build the signed app, put it in /Applications, and leave NO other copy behind.
#
#   bash Scripts/install_local.sh
#
# 2026-08-21 (#49). This exists because doing it by hand kept going wrong. Every
# build drops a PomoLight.app inside the project — dist/, build-release/export/,
# and build/Build/Products/Debug/ from the test build — and Spotlight indexes each
# one as an app. Searching "pomo" showed FOUR PomoLights, and Launch Services had
# eleven registered, seven of them pointing at directories that no longer existed
# (old temp dirs, a comparison worktree, three parallel-agent worktrees from
# 2026-08-15). macOS never unregisters an app just because its files are gone, so
# it only ever accumulated.
#
# Marking the build folders with .metadata_never_index was tried first and did not
# work — they were re-indexed as soon as the next build wrote into them. So this
# script takes the reliable route instead: after installing, the in-project copies
# are deleted, and it verifies that exactly one PomoLight.app is left anywhere.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="/Applications/PomoLight.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

echo "▸ Quitting a running PomoLight…"
# The copy below would otherwise land on top of a live binary.
pkill -x PomoLight 2>/dev/null || true
sleep 1

bash Scripts/build_app.sh

echo
echo "▸ Installing to ${DEST}…"   # braces: bash reads "$DEST…" as one name
rm -rf "$DEST"
cp -R dist/PomoLight.app "$DEST"

echo "▸ Verifying the installed copy…"
codesign --verify --strict --verbose=1 "$DEST"
SIGN_INFO=$(codesign -dv --verbose=2 "$DEST" 2>&1)
echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application" \
  || { echo "✗ The installed app is not Developer ID signed"; exit 1; }
echo "$SIGN_INFO" | grep -E "Authority=Developer ID Application|TeamIdentifier|Timestamp"

echo
echo "▸ Removing the in-project copies (this is the whole point)…"
# Unregister BEFORE deleting: lsregister -u needs the bundle to still be there to
# identify it. A path that is already gone stays in the database forever.
for p in dist/PomoLight.app \
         build-release/export/PomoLight.app \
         build-release/PomoLight.xcarchive/Products/Applications/PomoLight.app \
         build/Build/Products/Debug/PomoLight.app; do
  [ -d "$p" ] && "$LSREG" -u "$PWD/$p" >/dev/null 2>&1 || true
done
rm -rf build build-release dist
# Spotlight needs a moment to notice the deletions before we count.
sleep 5

echo "▸ Checking that exactly one copy is left…"
FAILED=0

ON_DISK=$(find "$HOME" /Applications -maxdepth 12 -name 'PomoLight.app' \
            -not -path '*/Trash/*' 2>/dev/null || true)
INDEXED=$(mdfind "kMDItemFSName == 'PomoLight.app'" 2>/dev/null || true)
REGISTERED=$("$LSREG" -dump 2>/dev/null | grep -oE "/[^ ]*PomoLight\.app[^ ]*" | sort -u || true)

report() {
  local label="$1" list="$2"
  local n=0
  [ -n "$list" ] && n=$(printf '%s\n' "$list" | wc -l | tr -d ' ')
  if [ "$n" -eq 1 ] && [ "$list" = "$DEST" ]; then
    printf '  ✅ %-18s 1 (%s)\n' "$label" "$DEST"
  else
    FAILED=1
    printf '  ❌ %-18s %s\n' "$label" "$n"
    [ -n "$list" ] && printf '%s\n' "$list" | sed 's/^/       /'
  fi
}
report "on disk" "$ON_DISK"
report "Spotlight" "$INDEXED"
report "Launch Services" "$REGISTERED"

echo
if [ "$FAILED" -ne 0 ]; then
  echo "❌ More than one PomoLight is still visible to the system."
  echo "   Stale Launch Services rows can be dropped one at a time:"
  echo "     $LSREG -u <path>"
  exit 1
fi
echo "✅ Installed. One PomoLight on this Mac, and no build copies left in the project."
echo "   Your settings were untouched — they live in"
echo "   ~/Library/Preferences/com.vismo.pomolight.plist, not in the app."
