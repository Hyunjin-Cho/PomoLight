#!/usr/bin/env bash
# Proves PomoLight quits while its settings sheet is open.
#
#   bash Scripts/quit_check.sh
#
# 2026-11-22 (#17). With the settings sheet open, macOS refused to quit the app —
# ⌘Q, Dock ▸ Quit, and Settings ▸ Remove PomoLight… (which then left a running app
# behind with its bundle in the Trash) all did nothing. That build passed all seven
# verify stages and was notarized: nothing ever launched the app with the sheet up.
# The fix (#14, `QuitClosesSheets`) leans on a SwiftUI-private class and on replacing
# the quit Apple Event handler — the kind of thing a macOS update undoes silently.
#
# Two ways in, because they are two different code paths:
#   1. terminate — the app opens the sheet and calls NSApp.terminate itself, as the
#      Quit menu item, Remove PomoLight… and an update install do.
#   2. Apple Event — the app opens the sheet and waits; this script sends it the
#      quit Apple Event, as Dock ▸ Quit, logging out and AppleScript do.
# Each must be gone within a few seconds, and must have reported the sheet open first.
#
# Negative-tested 2026-11-22: with `QuitClosesSheets.install()` taken out, both fail.
set -uo pipefail
cd "$(dirname "$0")/.."

APP_SRC="build/Build/Products/Debug/PomoLight.app"
[ -d "$APP_SRC" ] || { echo "✗ No Debug build at $APP_SRC — run the build stage first."; exit 1; }

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
WORK=$(mktemp -d)
APP="$WORK/PomoLight-quitcheck-$$.app"
PID=""
# Launching registers the copy with Launch Services; take that back (see uninstall_check.sh).
cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null
  "$LSREG" -u "$APP" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

cp -R "$APP_SRC" "$APP"

# The quit Apple Event goes to this copy's PID, never by bundle id — the owner's own
# PomoLight has the same one. NSRunningApplication.terminate() sends exactly the event
# the Dock sends.
SENDER="$WORK/send_quit"
cat > "$WORK/send_quit.swift" <<'SWIFT'
import AppKit
guard CommandLine.arguments.count == 2, let pid = pid_t(CommandLine.arguments[1]),
      let app = NSRunningApplication(processIdentifier: pid) else { exit(2) }
exit(app.terminate() ? 0 : 1)
SWIFT
swiftc -O -o "$SENDER" "$WORK/send_quit.swift" 2>/dev/null || { echo "✗ could not build the quit sender"; exit 1; }

# Fingerprinted through cfprefsd (`defaults export`), as in uninstall_check.sh.
real_prefs() { defaults export com.vismo.pomolight - 2>/dev/null | shasum | cut -c1-12; }
REAL_BEFORE=$(real_prefs)

launch() {   # $1 = POMO_QUIT_SELFTEST mode
  : > "$WORK/stderr.txt"
  PID=""
  open -n --env "POMO_QUIT_SELFTEST=$1" --stdout /dev/null --stderr "$WORK/stderr.txt" "$APP"
  for _ in $(seq 1 50); do
    PID=$(pgrep -f "$APP/Contents/MacOS/PomoLight" | head -1)
    [ -n "$PID" ] && return 0
    sleep 0.1
  done
  return 1
}
sheet_reported() { grep -q "QUITSELFTEST sheet open" "$WORK/stderr.txt" 2>/dev/null; }
gone_within() {   # $1 = tenths of a second
  for _ in $(seq 1 "$1"); do
    kill -0 "$PID" 2>/dev/null || { PID=""; return 0; }
    sleep 0.1
  done
  return 1
}
fail_case() {
  echo "❌ $1"
  [ -s "$WORK/stderr.txt" ] && sed -n '1,5p' "$WORK/stderr.txt" | sed 's/^/     /'
  [ -n "$PID" ] && { kill "$PID" 2>/dev/null; PID=""; }
  FAILED=1
}

FAILED=0

# 1. terminate, from inside — 5 s for the sheet, then 5 s to be gone.
if ! launch terminate; then
  fail_case "terminate: the app did not start"
elif ! gone_within 100; then
  if sheet_reported; then fail_case "terminate: still running 5 s after quitting with the sheet open"
  else fail_case "terminate: the sheet never opened, and the app is still running"; fi
elif ! sheet_reported; then
  fail_case "terminate: the app quit, but never reported the sheet open — nothing was proven"
else
  echo "  ✅ quit with the sheet open (NSApp.terminate — ⌘Q, Remove, update install)"
fi

# 2. the quit Apple Event, from outside.
if ! launch wait; then
  fail_case "Apple Event: the app did not start"
else
  for _ in $(seq 1 50); do sheet_reported && break; kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
  if ! sheet_reported; then
    fail_case "Apple Event: the sheet never opened"
  elif ! "$SENDER" "$PID"; then
    fail_case "Apple Event: could not send the quit event to PID $PID"
  elif ! gone_within 50; then
    fail_case "Apple Event: still running 5 s after the quit event with the sheet open"
  else
    echo "  ✅ quit with the sheet open (quit Apple Event — Dock, logout, AppleScript)"
  fi
fi

if [ "$(real_prefs)" != "$REAL_BEFORE" ]; then
  echo "❌ the check changed the real preferences (com.vismo.pomolight):"
  defaults export com.vismo.pomolight - 2>/dev/null | plutil -p - | sed 's/^/     /'
  FAILED=1
else
  echo "  ✅ the real settings are untouched"
fi

echo
[ "$FAILED" -eq 0 ] && { echo "✅ PASS — PomoLight quits with its settings sheet open."; exit 0; }
echo "❌ FAIL — see the lines marked ❌ above."
exit 1
