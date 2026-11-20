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

# 2026-11-20 (#69 F-3): 이 함수는 만들어진 날부터 실패를 통과로 찍었다. 예전엔
# `… | grep … || true` 다음 줄에서 `${PIPESTATUS[0]}` 를 봤는데, `|| true` 도 명령이라
# PIPESTATUS 를 자기 결과(0)로 덮어쓴다 — 그래서 컴파일 오류가 있어도 이 단계는 ✅ 였다.
# 이제는 파이프를 없앴다: 빌드 출력을 build/ 아래 로그 파일로 받고 xcodebuild 의 `$?` 를
# 직접 본 뒤, 보여 줄 줄만 그 파일에서 grep 한다. grep 의 종료 상태(일치 없음 = 1)는
# 빌드와 상관이 없으니 결과에 섞지 않는다.
quiet_build() {
  local log="build/verify-build-$1.log" status
  mkdir -p build
  xcodebuild build -project PomoLight.xcodeproj -scheme "$1" \
    -configuration Debug -destination 'platform=macOS' -derivedDataPath build >"$log" 2>&1
  status=$?
  grep -E "error:|warning: (unused|never)" "$log"
  if [ "$status" -ne 0 ]; then
    printf '  xcodebuild exited %d — full log: %s\n' "$status" "$log"
    # 오류 줄 없이 실패하는 경우(서명·도구 문제)도 있다 — 그땐 끝부분이라도 보인다.
    grep -q "error:" "$log" || tail -15 "$log"
    return 1
  fi
}

# 2026-11-20 (#69 F-14): 예전엔 `xcodegen generate … || true` 였다. 실패하면 낡은
# PomoLight.xcodeproj 로 빌드하게 되는데(새 파일이 빠진 채) 아무도 모른다. 이제 단계로 센다.
generate_project() {
  local out
  if ! out=$(xcodegen generate 2>&1); then
    printf '%s\n' "$out" | tail -15
    return 1
  fi
}

stage "Generate the Xcode project (project.yml)" generate_project
stage "Build the app (the half the tests never compile)" quiet_build PomoLight
BUILD_OK=1
[ ${#FAILED[@]} -eq 0 ] || BUILD_OK=0

# 2026-11-20 (#69 F-3): 프로젝트 생성이나 빌드가 실패하면 build/ 에는 예전에 만든
# Debug 앱이 그대로 남아 있다. 아래 두 단계는 그 앱을 띄우므로, 그대로 돌리면 "낡은 앱이
# 통과했다"를 ✅ 로 찍는다. 그래서 그런 회차에는 돌리지 않고 실패로 센다 — 증명된 게 없으니까.
needs_fresh_app() {
  if [ "$BUILD_OK" -ne 1 ]; then
    echo "  not run — generating or building the app failed, so build/ may hold an older app."
    return 1
  fi
  "$@"
}
stage "Unit tests" bash -c 'xcodebuild test -project PomoLight.xcodeproj -scheme PomoLightTests -destination "platform=macOS" -derivedDataPath build 2>&1 | grep -E "Executed .* tests|error:" | tail -2; [ "${PIPESTATUS[0]}" -eq 0 ]'
stage "Contrast audit (every theme x light/dark)" bash Scripts/contrast_audit.sh
# The audit proves the palette CAN be legible; this proves the app actually uses it
# that way. Three separate controls had already been shipped drawing a FILL role as
# a foreground, each invisible on every theme (2026-08-21).
stage "Palette roles (no FILL colour drawn as a foreground)" bash Scripts/palette_role_check.sh
stage "Silent launch (starting the app must not open the audio device)" needs_fresh_app bash Scripts/silent_launch_check.sh
# Last, because it needs the Debug build the first stage produced. Uninstalling is
# the one feature nobody can rehearse by hand — every try costs the tester their
# own install — so it is checked against a throwaway copy instead (#52).
stage "Uninstall (removing PomoLight really removes it)" needs_fresh_app bash Scripts/uninstall_check.sh

printf '\n'
if [ ${#FAILED[@]} -eq 0 ]; then
  printf '\033[1m✅ All checks passed.\033[0m\n'
  exit 0
fi
printf '\033[1m❌ %d check(s) failed:\033[0m\n' "${#FAILED[@]}"
printf '   · %s\n' "${FAILED[@]}"
exit 1
