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
# launch of the real binary: it builds six AppModels, and therefore six
# ChimePlayers, renders offscreen and terminates itself. `debugForceFinish()`
# sets the finished phase WITHOUT calling onFinish, so nothing legitimately plays
# — every CoreAudio event this sees is a regression.
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
trap 'rm -rf "$SHOTS"' EXIT

# A blank or failed render still writes a PNG, just a tiny one — the real screens
# are 170-460 KB, a flat colour compresses to a few. 20 KB sits far from both.
MIN_PNG_BYTES=20480

# The log is queried by PID, so the window must start BEFORE the process does or
# a fast exit can leave the query looking at the wrong slice of time.
START="$(date '+%Y-%m-%d %H:%M:%S')"
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

# Captured once, not queried twice: `log show | head` under `pipefail` exits 141
# on SIGPIPE, which would report a broken pipe as the script's own failure.
FOUND=$(/usr/bin/log show --start "$START" \
  --predicate "processIdentifier == $PID AND subsystem == \"com.apple.coreaudio\"" \
  --style compact 2>/dev/null || true)
EVENTS=$(printf '%s' "$FOUND" | grep -c "coreaudio" || true)

if [ "$EVENTS" -eq 0 ]; then
  echo "✅ PASS — started cleanly, rendered $RENDERED screens, touched the audio device 0 times."
  exit 0
fi

echo "❌ FAIL — starting the app produced $EVENTS CoreAudio event(s)."
echo
echo "   Something now opens the output device before any sound is meant to play."
echo "   On this hardware that is an audible click on every launch. Look for a"
echo "   reference to AVAudioEngine's outputNode / mainMixerNode that runs outside"
echo "   ChimePlayer.prepareGraphIfNeeded() — merely TOUCHING mainMixerNode opens"
echo "   the device, no start() required."
echo
printf '%s\n' "$FOUND" | sed -n '2,9p'
exit 1
