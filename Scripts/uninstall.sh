#!/usr/bin/env bash
# Remove PomoLight and everything it has ever put on this Mac.
#
#   bash Scripts/uninstall.sh                 # list what is there, delete nothing
#   bash Scripts/uninstall.sh --yes           # actually delete it
#   bash Scripts/uninstall.sh --yes --keep-settings
#   bash Scripts/uninstall.sh --yes --leftovers-only   # keep the app AND settings,
#                                                      # clear only what old builds left
#
# 2026-08-21 (#50). macOS removes nothing when you drag an app to the Trash — not
# its preferences, not its containers, not its Launch Services row. That is true
# of every Mac app, and it is why "I deleted it and it is still there" is a fair
# complaint. PomoLight should be able to answer it.
#
# The honest news first: a current install leaves exactly ONE file behind,
# ~/Library/Preferences/com.vismo.pomolight.plist (4 KB of settings and window
# positions). The app is not sandboxed and has no App Group, so no container is
# ever created for it. Everything else on this list is either from the widget,
# which was removed in PR #33 and never shipped publicly, or is written by macOS
# itself (crash reports).
#
# Listing is the default on purpose. This deletes things inside ~/Library, so it
# should be possible to read the list first and then decide.
set -uo pipefail

APPLY=0
KEEP_SETTINGS=0
LEFTOVERS_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --yes|-y)          APPLY=1 ;;
    --keep-settings)   KEEP_SETTINGS=1 ;;
    # For someone who still uses PomoLight but wants the widget's containers gone.
    # That is the common case right after an upgrade, and without this the only way
    # to reach those files was to uninstall the app you meant to keep.
    --leftovers-only)  LEFTOVERS_ONLY=1; KEEP_SETTINGS=1 ;;
    -h|--help)         sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (see --help)"; exit 2 ;;
  esac
done

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Every path is spelled out. No globbing over directories we do not own — the two
# wildcards below are filenames macOS stamps with a UUID.
APP="/Applications/PomoLight.app"

# 🔒 The block between these markers is mirrored by `Uninstaller.tracePaths` in
# Sources/Support/Uninstaller.swift, and UninstallerTests reads THIS FILE and fails
# if the two lists differ. Paths are relative to ~/Library and the order matters to
# the test. Editing one side alone is meant to break the build: a shell script and
# an app that disagree about what "remove everything" means is precisely the drift
# that made the old contrast audit lie for weeks.
# BEGIN library-paths
LIBRARY_PATHS=(
  "Preferences/com.vismo.pomolight.plist"
  "Preferences/group.com.vismo.pomolight.plist"
  "Containers/com.vismo.pomolight.widget"
  "Group Containers/group.com.vismo.pomolight"
  "Application Scripts/com.vismo.pomolight.widget"
  "Application Scripts/group.com.vismo.pomolight"
  "Application Scripts/com.vismo.pomolight"
  "Saved Application State/com.vismo.pomolight.savedState"
  "Caches/com.vismo.pomolight"
  "HTTPStorages/com.vismo.pomolight"
)
# END library-paths

abs() { printf '%s/Library/%s' "$HOME" "$1"; }
SETTINGS="$(abs "${LIBRARY_PATHS[0]}")"

CURRENT=("$APP")
WIDGET_ERA=()
for i in 1 2 3 4 5 6; do WIDGET_ERA+=("$(abs "${LIBRARY_PATHS[$i]}")"); done
SYSTEM_WRITTEN=()
for i in 7 8 9; do SYSTEM_WRITTEN+=("$(abs "${LIBRARY_PATHS[$i]}")"); done
# Crash reports and the widget's daemon transcript sit under paths macOS names, so
# these two are collected rather than hard-coded.
while IFS= read -r p; do [ -n "$p" ] && SYSTEM_WRITTEN+=("$p"); done < <(
  find "$HOME/Library/Application Support/CrashReporter" -maxdepth 1 \
       -name 'PomoLight_*.plist' 2>/dev/null
)
while IFS= read -r p; do [ -n "$p" ] && WIDGET_ERA+=("$p"); done < <(
  find "$HOME/Library/Daemon Containers" -maxdepth 4 \
       -name 'com.vismo.pomolight.widget' 2>/dev/null
)

FOUND=()
show() {
  local title="$1"; shift
  local printed=0
  for p in "$@"; do
    [ -e "$p" ] || continue
    if [ "$printed" -eq 0 ]; then printf '\n  %s\n' "$title"; printed=1; fi
    printf '    %-72s %s\n' "${p/#$HOME/~}" "$(du -sh "$p" 2>/dev/null | cut -f1)"
    FOUND+=("$p")
  done
}

echo "▸ PomoLight traces on this Mac"
if [ "$LEFTOVERS_ONLY" -eq 1 ]; then
  [ -e "$APP" ] && printf '\n  The app (kept — --leftovers-only)\n    %s\n' "$APP"
else
  show "The app" "${CURRENT[@]}"
fi
if [ "$KEEP_SETTINGS" -eq 1 ]; then
  [ -e "$SETTINGS" ] && printf '\n  Settings (kept — --keep-settings)\n    %s\n' "${SETTINGS/#$HOME/~}"
else
  show "Settings" "$SETTINGS"
fi
show "Left by builds that no longer exist — the widget (PR #33) and the
        sandbox change that was reverted the same week. Nothing reads these." "${WIDGET_ERA[@]}"
show "Written by macOS, not by the app" "${SYSTEM_WRITTEN[@]}"

if [ "${#FOUND[@]}" -eq 0 ]; then
  echo
  echo "✅ Nothing to remove."
  exit 0
fi

if [ "$APPLY" -eq 0 ]; then
  echo
  echo "  ${#FOUND[@]} item(s) listed. Nothing was deleted."
  if [ "$LEFTOVERS_ONLY" -eq 1 ]; then
    echo "  Run again with --yes --leftovers-only to clear them. The app and your"
    echo "  settings stay exactly as they are."
  else
    echo "  Run again with --yes to remove them — add --keep-settings to keep your"
    echo "  themes, sounds and durations, or --leftovers-only to keep the app too."
  fi
  exit 0
fi

echo
echo "▸ Quitting PomoLight…"
pkill -x PomoLight 2>/dev/null || true
sleep 1

# Unregister while the bundle still exists: lsregister identifies it by reading it,
# so a path deleted first stays in the database with no way to name it again.
# Skipped when the app is staying — unregistering an installed app would hide it
# from Spotlight while leaving it perfectly runnable, which is its own confusion.
if [ "$LEFTOVERS_ONLY" -eq 0 ] && [ -d "$APP" ]; then
  echo "▸ Unregistering from Launch Services…"
  "$LSREG" -u "$APP" >/dev/null 2>&1 || true
fi

# Same ordering lesson as the in-app uninstall: cfprefsd caches preference domains
# and flushes them when it exits, so stopping it AFTER deleting a plist writes the
# plist back. Stop it first, then delete.
if [ "$KEEP_SETTINGS" -eq 0 ]; then
  echo "▸ Flushing the preferences cache before deleting…"
  killall cfprefsd 2>/dev/null || true
  sleep 1
fi

echo "▸ Removing…"
for p in "${FOUND[@]}"; do
  if rm -rf "$p" 2>/dev/null; then
    printf '    removed  %s\n' "${p/#$HOME/~}"
  else
    printf '    ⚠️  could not remove (macOS may protect it): %s\n' "${p/#$HOME/~}"
  fi
done

# Once more, now that the files are gone: anything that read a preference during
# the deletion above would have repopulated the cache.
echo "▸ Flushing the preferences cache…"
killall cfprefsd 2>/dev/null || true

echo
# 2026-08-21: this used to be `find … -iname '*pomolight*'`, which reported three
# things that were not leftovers at all — Xcode's DerivedData, an unrelated tool's
# cache that merely had the project name in its path, and the executable INSIDE the
# app we had deliberately kept. A successful run that prints "⚠️ Still present" is
# a check people learn to ignore, so it now re-reads the very list it just acted on.
LEFT=""
for p in "${FOUND[@]}"; do [ -e "$p" ] && LEFT="$LEFT$p"$'\n'; done
LEFT=$(printf '%s' "$LEFT" | sed '/^$/d')
if [ -z "$LEFT" ]; then
  echo "✅ Removed. Nothing left but what you asked to keep."
else
  echo "⚠️  Still present:"
  printf '%s\n' "$LEFT" | sed "s|$HOME|~|" | sed 's/^/    /'
fi
echo
echo "One thing this cannot touch: the entry in System Settings ▸ Notifications."
echo "macOS keeps that itself and drops it on its own schedule."
