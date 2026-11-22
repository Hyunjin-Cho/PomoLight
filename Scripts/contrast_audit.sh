#!/usr/bin/env bash
# Runs the WCAG contrast audit against the app's REAL color derivation.
#
# The audit used to be a single self-contained .swift script, which meant it kept
# its own copy of the palette math — a copy that could silently disagree with the
# app. Now it compiles the actual sources, so it cannot drift.
#
# Usage: bash Scripts/contrast_audit.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
# 2026-11-22 (#13): under macOS's bash 3.2, `set -e` + `set -u` + an EXIT trap make an unbound variable exit 0
# — even with `rc=$?; exit $rc` in the trap (measured; `set -u` alone, or no trap, exits 1). verify.sh would
# have shown a crashed check as ✅, so the trap also checks that the script reached one of its intended ends.
REACHED_END=0
on_exit() {
  local rc=$?
  rm -rf "$OUT"
  if [ "$rc" -eq 0 ] && [ "$REACHED_END" -ne 1 ]; then
    echo "❌ FAIL — the check stopped before its end (an error bash 3.2 reports as success)." >&2
    exit 1
  fi
  exit "$rc"
}
trap on_exit EXIT

swiftc -O -swift-version 5 -o "$OUT/contrast_audit" \
  Sources/Theme/Color+Contrast.swift \
  Sources/Theme/Theme.swift \
  Scripts/ContrastAudit.swift

"$OUT/contrast_audit"
REACHED_END=1
