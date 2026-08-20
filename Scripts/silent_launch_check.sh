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

# The log is queried by PID, so the window must start BEFORE the process does or
# a fast exit can leave the query looking at the wrong slice of time.
START="$(date '+%Y-%m-%d %H:%M:%S')"
POMO_SNAPSHOT="$SHOTS" "$APP" >/dev/null 2>&1 &
PID=$!
echo "▸ Launched PID $PID (offscreen snapshot mode)…"
wait "$PID" || true

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
  echo "✅ PASS — starting the app touched the audio device 0 times."
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
