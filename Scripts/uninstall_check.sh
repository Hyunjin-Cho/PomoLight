#!/usr/bin/env bash
# Proves that removing PomoLight from inside PomoLight actually removes it.
#
#   bash Scripts/uninstall_check.sh
#
# 2026-08-21 (#52). Uninstalling is the one feature that cannot be tried by hand
# without consequences — every rehearsal costs the tester their own install and
# their own settings — so it was the one feature with no check on it. It also went
# wrong the first time it was run for real: the app went to the Trash correctly and
# the preferences file came straight back, holding a single `pl.showInMenuBar`
# written by SwiftUI tearing down the menu-bar scene half a second after the domain
# had been deleted. "I removed it and it is still there" is exactly the complaint
# the feature exists to answer, so it needs a check that runs on every build.
#
# This drives the REAL uninstall (`Uninstaller.performUninstall`) with substituted
# targets: a throwaway copy of the app and a throwaway preferences suite. Same
# ordering, same detached cleanup, nothing of the tester's at stake.
#
# It has been negative-tested: putting the old cleanup order back (delete the file,
# then stop cfprefsd) makes this script fail with the preferences file present and
# empty — the cache flushing itself out on the way down.
set -uo pipefail
cd "$(dirname "$0")/.."

APP_SRC="build/Build/Products/Debug/PomoLight.app"
[ -d "$APP_SRC" ] || { echo "✗ No Debug build at $APP_SRC — run the build stage first."; exit 1; }

LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

WORK=$(mktemp -d)
SUITE="pl.uninstallcheck.$$"
PLIST="$HOME/Library/Preferences/$SUITE.plist"
# 2026-11-20 (#70 F-6): 사본 이름이 그냥 `PomoLight.app` 이었고, 정리 단계는
# `~/.Trash/PomoLight.app` 을 무조건 지웠다. 그런데 휴지통에 이미 같은 이름이 있으면 macOS 는
# 새로 들어온 것에 다른 이름("PomoLight 2.app" 류)을 붙인다 — 그러면 이 검사는 사람이 원래
# 버려 둔 진짜 앱을 영구 삭제하고, 자기 사본은 휴지통에 남긴 채 "휴지통에 없다" 로 떨어졌다.
# 이제 사본 이름을 이 회차만의 것으로 만들고, 그 이름이 휴지통에 이미 있으면 시작하지 않는다.
# (번들 이름은 바뀌어도 실행 파일·번들 ID 는 그대로라 제거 코드가 하는 일은 같다.)
APP_NAME="PomoLight-uninstallcheck-$$.app"
APP="$WORK/$APP_NAME"
TRASHED="$HOME/.Trash/$APP_NAME"
if [ -e "$TRASHED" ]; then
  echo "✗ $TRASHED already exists — refusing to run, so nothing of yours is overwritten or deleted."
  rm -rf "$WORK"
  exit 1
fi

# 2026-08-21: the first version of this script left its throwaway copies REGISTERED
# with Launch Services — running it launches an app, and macOS remembers every app
# it has ever launched, whether or not the files still exist. Six runs later
# `install_local.sh` failed its own "exactly one PomoLight" check, listing six
# temp directories and a Trash entry. A check that pollutes what another check
# measures is worse than no check, so this one takes its registrations back.
cleanup() {
  "$LSREG" -u "$TRASHED" >/dev/null 2>&1 || true
  "$LSREG" -u "$APP" >/dev/null 2>&1 || true
  rm -rf "$WORK" "$PLIST" "$TRASHED"
}
trap cleanup EXIT

# Fingerprint the tester's real install before touching anything. The self-test
# runs the real code, so "it did not reach past its substituted targets" is the
# claim that most needs proving.
REAL_PLIST="$HOME/Library/Preferences/com.vismo.pomolight.plist"
real_state() {
  printf '%s|%s' \
    "$(stat -f '%m %z' "$REAL_PLIST" 2>/dev/null || echo absent)" \
    "$([ -d /Applications/PomoLight.app ] && echo installed || echo absent)"
}
BEFORE=$(real_state)

cp -R "$APP_SRC" "$APP"
echo "▸ Throwaway app:   $APP"
echo "▸ Throwaway suite: $SUITE"

# Run it in the foreground and wait — the app performs the uninstall and exits.
POMO_UNINSTALL_SELFTEST="$SUITE" "$APP/Contents/MacOS/PomoLight" >/dev/null 2>"$WORK/stderr.txt"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  echo "❌ FAIL — the app exited $STATUS instead of performing the uninstall."
  [ -s "$WORK/stderr.txt" ] && sed -n '1,10p' "$WORK/stderr.txt"
  exit 1
fi
grep -q "SELFTEST performed" "$WORK/stderr.txt" || {
  echo "❌ FAIL — the app exited cleanly without running the self-test."
  echo "   (POMO_UNINSTALL_SELFTEST is DEBUG-only; a Release build cannot be checked.)"
  exit 1
}

# The detached cleanup waits for the process, stops cfprefsd, then deletes. Give it
# room: the two sleeps inside it are half a second each.
sleep 4

FAILED=0

# 1. The bundle must be in the Trash, and gone from where it was.
if [ -d "$APP" ]; then
  echo "❌ the app is still at $APP"
  FAILED=1
elif [ ! -d "$TRASHED" ]; then
  echo "❌ the app left $APP but is not in the Trash — it should be recoverable"
  FAILED=1
else
  echo "  ✅ app moved to the Trash (recoverable, not destroyed)"
  # Left for `cleanup` to unregister and remove — deleting it here would strand its
  # Launch Services row with no path left to name it by.
fi

# 2. The preferences file must be gone AND STAY gone. This is the one that failed
#    for real: the self-test writes two settings AFTER the uninstall, exactly as
#    SwiftUI did on the way out.
if [ -f "$PLIST" ]; then
  echo "❌ the preferences file came back:"
  plutil -p "$PLIST" | sed 's/^/       /'
  FAILED=1
else
  echo "  ✅ preferences deleted, and later writes did not resurrect them"
fi

# 3. The tester's own install and settings must be exactly as they were. This is
#    the check that lets the whole thing run unattended: the real code ran, and it
#    stayed inside the targets it was handed.
if [ "$(real_state)" != "$BEFORE" ]; then
  echo "❌ the check touched the real install"
  echo "     before: $BEFORE"
  echo "     after:  $(real_state)"
  FAILED=1
else
  echo "  ✅ the real install and its settings are untouched"
fi

echo
[ "$FAILED" -eq 0 ] && { echo "✅ PASS — the in-app uninstall removes the app and its settings, for good."; exit 0; }
echo "❌ FAIL — removing PomoLight did not remove PomoLight."
exit 1
