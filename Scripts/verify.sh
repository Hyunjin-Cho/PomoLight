#!/usr/bin/env bash
# Everything that can say "this is broken" without a human looking at the screen.
#
#   bash Scripts/verify.sh
#
# The order matters: each stage is cheap enough to be worth running before the
# next one, and the first two exist because of a specific trap. `xcodebuild test`
# uses a HOST-LESS bundle that compiles only TimerEngine, DialFrameRate, Theme,
# Color+Contrast and SettingsStore — it never compiles AppModel, AppDelegate or a
# single view. A green suite therefore says nothing about whether the app builds at
# all, and two separate agents were caught by that on 2026-08-15. So the build runs
# first, and its job is to compile the code the tests cannot see.
set -uo pipefail
cd "$(dirname "$0")/.."

FAILED=()
stage() {
  local name="$1"; shift
  printf '\n\033[1m▸ %s\033[0m\n' "$name"
  if "$@"; then printf '  ✅ %s\n' "$name"
  else FAILED+=("$name"); printf '  ❌ %s\n' "$name"; fi
}

quiet_build() {
  xcodebuild build -project PomoLight.xcodeproj -scheme "$1" \
    -configuration Debug -destination 'platform=macOS' -derivedDataPath build 2>&1 \
    | grep -E "error:|warning: (unused|never)" || true
  # grep's status is about matches, not about the build — ask xcodebuild directly.
  [ "${PIPESTATUS[0]}" -eq 0 ]
}

xcodegen generate >/dev/null 2>&1 || true

stage "Build the app (the half the tests never compile)" quiet_build PomoLight
stage "Unit tests" bash -c 'xcodebuild test -project PomoLight.xcodeproj -scheme PomoLightTests -destination "platform=macOS" -derivedDataPath build 2>&1 | grep -E "Executed .* tests|error:" | tail -2; [ "${PIPESTATUS[0]}" -eq 0 ]'
stage "Contrast audit (15 themes x light/dark)" bash Scripts/contrast_audit.sh
# The audit proves the palette CAN be legible; this proves the app actually uses it
# that way. Three separate controls had already been shipped drawing a FILL role as
# a foreground, each invisible on every theme (2026-08-21).
stage "Palette roles (no FILL colour drawn as a foreground)" bash Scripts/palette_role_check.sh
stage "Silent launch (starting the app must not open the audio device)" bash Scripts/silent_launch_check.sh

printf '\n'
if [ ${#FAILED[@]} -eq 0 ]; then
  printf '\033[1m✅ All checks passed.\033[0m\n'
  exit 0
fi
printf '\033[1m❌ %d check(s) failed:\033[0m\n' "${#FAILED[@]}"
printf '   · %s\n' "${FAILED[@]}"
exit 1
