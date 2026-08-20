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
trap 'rm -rf "$OUT"' EXIT

swiftc -O -swift-version 5 -o "$OUT/contrast_audit" \
  Sources/Theme/Color+Contrast.swift \
  Sources/Theme/Theme.swift \
  Scripts/ContrastAudit.swift

"$OUT/contrast_audit"
