#!/usr/bin/env bash
# Fails if simply STARTING PomoLight opens the audio device.
#
# Why this exists (2026-08-21). Twice in one day the owner heard a "tick" from a
# Mac where nothing was playing. It was not the alarm and not a notification: the
# chime player wired its render graph in `init`, and touching
# `engine.mainMixerNode` is what sends CoreAudio off to open the default output
# device. The speakers answer that with an audible click. The unified log showed
# AUHAL SelectDevice and a DefaultDeviceAggregate being built ~150 ms BEFORE
# applicationDidFinishLaunching, on every launch, with no playback anywhere near
# it. No unit test could catch that — the test bundle is host-less and never
# constructs the app — so it took a human noticing a noise, twice.
#
# The check runs the DEBUG snapshot renderer (POMO_SNAPSHOT), which is a real
# launch of the real binary: the app's own AppModel — and with it the one real
# ChimePlayer — comes up as it does for a person, six screens render offscreen,
# and the app terminates itself. (2026-11-22, #19: this said "six AppModels, and
# therefore six ChimePlayers"; since 2026-08-21 the six snapshot models use
# InertAlarm, so the app's own player is the one being checked.)
# `debugForceFinish()` sets the finished phase WITHOUT calling onFinish, so nothing
# legitimately plays — every CoreAudio event this sees is a regression.
#
#   bash Scripts/silent_launch_check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Debug/PomoLight.app/Contents/MacOS/PomoLight"
if [ ! -x "$APP" ]; then
  echo "▸ No Debug build yet — building…"
  xcodebuild build -project PomoLight.xcodeproj -scheme PomoLight \
    -configuration Debug -destination 'platform=macOS' -derivedDataPath build \
    >/dev/null 2>&1 || { echo "✗ Debug build failed"; exit 1; }
fi

SHOTS="$(mktemp -d)"
# 2026-11-22 (#13): under macOS's bash 3.2, `set -e` + `set -u` + an EXIT trap make an unbound variable exit 0
# — even with `rc=$?; exit $rc` in the trap (measured; `set -u` alone, or no trap, exits 1). verify.sh would
# have shown a crashed check as ✅, so the trap also checks that the script reached one of its intended ends.
REACHED_END=0
on_exit() {
  local rc=$?
  rm -rf "$SHOTS"
  if [ "$rc" -eq 0 ] && [ "$REACHED_END" -ne 1 ]; then
    echo "❌ FAIL — the check stopped before its end (an error bash 3.2 reports as success)." >&2
    exit 1
  fi
  exit "$rc"
}
trap on_exit EXIT

# A blank or failed render still writes a PNG, just a tiny one — the real screens
# are 170-460 KB, a flat colour compresses to a few. 20 KB sits far from both.
MIN_PNG_BYTES=20480

# The log is queried by PID, so the window must start BEFORE the process does or
# a fast exit can leave the query looking at the wrong slice of time.
START="$(date '+%Y-%m-%d %H:%M:%S')"
# 2026-11-22 (#16): this launch once wrote `pl.showInMenuBar` into the owner's real
# preferences. Fingerprinted through cfprefsd (`defaults export`), not the file — the
# file is written seconds later, which is how the write surfaced in the NEXT check.
real_prefs() { defaults export com.vismo.pomolight - 2>/dev/null | shasum | cut -c1-12; }
REAL_BEFORE=$(real_prefs)
POMO_SNAPSHOT="$SHOTS" "$APP" >/dev/null 2>"$SHOTS/stderr.txt" &
PID=$!
echo "▸ Launched PID $PID (offscreen snapshot mode)…"
# 🚨 2026-08-21: this used to be `wait "$PID" || true`, which threw the exit code
# away. Combined with the CoreAudio count below that made the check unable to
# fail in the one direction that matters most: an app that CRASHES on launch
# touches the audio device zero times, so it scored a clean pass. Proven with a
# stand-in binary that exits immediately — the check said PASS. "Started quietly"
# and "never started" have to be told apart, so the exit status is kept, and the
# renders it was supposed to produce are counted below.
EXIT_CODE=0
wait "$PID" || EXIT_CODE=$?

if [ "$EXIT_CODE" -ne 0 ]; then
  echo "❌ FAIL — the app exited $EXIT_CODE instead of rendering and quitting cleanly."
  echo
  echo "   It did not get far enough to make a sound, which is why the audio check"
  echo "   below would have passed. Something is wrong at startup, not with audio."
  [ -s "$SHOTS/stderr.txt" ] && { echo; sed -n '1,15p' "$SHOTS/stderr.txt"; }
  exit 1
fi

if [ "$(real_prefs)" != "$REAL_BEFORE" ]; then
  echo "❌ FAIL — the snapshot run changed the real preferences (com.vismo.pomolight):"
  defaults export com.vismo.pomolight - 2>/dev/null | plutil -p - | sed 's/^/     /'
  echo "   A check launch must leave them alone. (If the real PomoLight was running and"
  echo "   you changed a setting during the check, run it again.)"
  exit 1
fi

# Exit 0 is not proof it drew anything: the renderer writes one PNG per screen and
# says so on stderr. No files, or suspiciously small ones, means the view tree came
# up empty — invisible to a process-level check, and exactly the kind of breakage
# nobody notices until it ships.
RENDERED=$(find "$SHOTS" -name "*.png" | wc -l | tr -d ' ')
if [ "$RENDERED" -eq 0 ]; then
  echo "❌ FAIL — the app exited cleanly but rendered no screens at all."
  echo "   Expected PNGs in the POMO_SNAPSHOT directory; found none."
  [ -s "$SHOTS/stderr.txt" ] && { echo; sed -n '1,15p' "$SHOTS/stderr.txt"; }
  exit 1
fi

TINY=$(find "$SHOTS" -name "*.png" -size -"${MIN_PNG_BYTES}"c | head -5)
if [ -n "$TINY" ]; then
  echo "❌ FAIL — some screens rendered nearly empty (under $((MIN_PNG_BYTES / 1024)) KB):"
  printf '   · %s\n' $(basename -a $TINY)
  echo "   A flat, contentless image compresses to almost nothing; the real screens"
  echo "   are 170-460 KB. The view tree is drawing, but not drawing the app."
  exit 1
fi

# The unified log is written asynchronously; give it a moment to settle before
# concluding "nothing happened", or this passes for the wrong reason.
/bin/sleep 2

# 2026-11-20 (#69 F-14): 예전엔 아래 조회가 `2>/dev/null || true` 였다. 그러면 로그를
# 아예 못 읽은 경우(권한·잘못된 조건식·`log` 실패)도 "CoreAudio 0건" 이 되어 ✅ 였다 —
# "조용히 떴다" 와 "못 봤다" 가 같은 결과였다. 이제 두 가지를 따로 확인한다.
#   1) `log show` 가 실패하면(종료 상태 ≠ 0) 그 자체로 ❌.
#   2) 대조군: 같은 PID·같은 시간대의 로그가 한 줄이라도 보여야 한다. 앱은 뜨기만 해도
#      시스템 프레임워크가 몇 줄씩 남기므로, 0줄이면 "소리가 없었다" 가 아니라 "로그를 못
#      봤다" 다. 로그는 비동기로 쓰이니 조금 기다리며 몇 번 다시 본다.
LOG_ERR="$SHOTS/log_show_stderr.txt"
read_log() {
  # $1 = predicate. Prints the compact log; returns log show's own exit status.
  /usr/bin/log show --start "$START" --predicate "$1" --style compact 2>"$LOG_ERR"
}
log_unreadable() {
  echo "❌ FAIL — could not read the unified log (log show exited $1)."
  echo "   This is not a pass: with no log there is no way to tell a silent launch"
  echo "   from one that opened the audio device."
  [ -s "$LOG_ERR" ] && { echo; sed -n '1,5p' "$LOG_ERR"; }
  exit 1
}

SEEN=0
for _ in 1 2 3; do
  LOG_STATUS=0
  ALL=$(read_log "processIdentifier == $PID") || LOG_STATUS=$?
  [ "$LOG_STATUS" -eq 0 ] || log_unreadable "$LOG_STATUS"
  SEEN=$(printf '%s\n' "$ALL" | grep -c "\[$PID:" || true)
  [ "$SEEN" -gt 0 ] && break
  /bin/sleep 2
done
if [ "$SEEN" -eq 0 ]; then
  echo "❌ FAIL — the unified log shows nothing at all for PID $PID since $START."
  echo "   Every launch leaves some lines there, so this means the log could not be"
  echo "   seen, not that the app was quiet. The CoreAudio count would be meaningless."
  exit 1
fi

# Captured once, not queried twice: `log show | head` under `pipefail` exits 141
# on SIGPIPE, which would report a broken pipe as the script's own failure.
LOG_STATUS=0
FOUND=$(read_log "processIdentifier == $PID AND subsystem == \"com.apple.coreaudio\"") || LOG_STATUS=$?
[ "$LOG_STATUS" -eq 0 ] || log_unreadable "$LOG_STATUS"
EVENTS=$(printf '%s' "$FOUND" | grep -c "coreaudio" || true)

if [ "$EVENTS" -eq 0 ]; then
  echo "✅ PASS — started cleanly, rendered $RENDERED screens, touched the audio device 0 times"
  echo "   (the log was readable: $SEEN line(s) from this PID, none from CoreAudio)."
  REACHED_END=1
  exit 0
fi

echo "❌ FAIL — starting the app produced $EVENTS CoreAudio event(s)."
echo
echo "   Something now opens the output device before any sound is meant to play."
echo "   On this hardware that is an audible click on every launch. Look for a"
echo "   reference to AVAudioEngine's outputNode / mainMixerNode that runs outside"
echo "   ChimePlayer.graph() — merely TOUCHING mainMixerNode opens"
echo "   the device, no start() required."
echo
printf '%s\n' "$FOUND" | sed -n '2,9p'
exit 1
