#!/usr/bin/env bash
# Fails if any view draws a FILL palette role as a FOREGROUND.
#
# 2026-08-21. `ResolvedPalette` splits its roles into FILL ("safe to draw ON, never
# safe to draw WITH") and FOREGROUND ("pushed until it clears a tier"), and
# ContrastTests already proves the split holds for every theme — including the
# negative half, that raw `accent` CANNOT clear 3:1 anywhere. What no check covered
# was whether the app obeys it. It kept not obeying it:
#
#   · the donation heart asked for `accent` from the day it was written (fixed #26)
#   · the alarm-sound radio marked the SELECTED row with it — 1.20:1 on Lime, so
#     the selected row was fainter than the three unselected ones
#   · the menu-bar button handed `accent` to `.borderedProminent` as a tint, and
#     AppKit put a white label on it at 2.27:1 (Magenta)
#
# Three of the same mistake means the rule needed a machine behind it, not another
# comment. Whole-word `accent` only — `accentSoft` is a fill for fills and fine —
# and only where a colour is being drawn WITH: `.foregroundStyle` and `.tint`.
# Passing `accent` as a named argument (`glow:`, `soft:`) is what it is for.
set -uo pipefail
cd "$(dirname "$0")/.."

scan() {
  # $1 = directory to scan. Prints offending "file:line:text" lines, if any.
  # Comment lines are dropped: the fixes deliberately quote the old broken call in
  # a `// this used to be .tint(palette.accent)` note, and a check that trips over
  # its own postmortem is a check people delete.
  grep -rnE '\.(foregroundStyle|tint)\([^)]*\baccent\b' "$1" --include='*.swift' \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//' \
    | grep -v 'accentSoft' || true
}

# Negative test first: the check has to be able to fail, or a green run means
# nothing. Build a throwaway view that breaks the rule and confirm it is caught.
PROBE=$(mktemp -d)
trap 'rm -rf "$PROBE"' EXIT
cat > "$PROBE/Offender.swift" <<'SWIFT'
import SwiftUI
struct Offender: View {
    let palette: Palette
    var body: some View { Image(systemName: "circle").foregroundStyle(palette.accent) }
}
SWIFT
if [ -z "$(scan "$PROBE")" ]; then
  echo "❌ FAIL — the check itself is broken: it did not flag a deliberate violation."
  exit 1
fi

HITS=$(scan Sources)
if [ -n "$HITS" ]; then
  echo "❌ FAIL — a FILL role is being drawn as a foreground:"
  echo
  echo "$HITS" | sed 's/^/   /'
  echo
  # 2026-11-19 (#66): re-measured for the eight pastels (was 1.20:1 Lime … 3.13:1 Indigo).
  echo '   `accent` is a FILL. On the light surface it measures 1.19:1 (Yellow) … 1.53:1'
  echo "   (Pink), where an icon needs 3:1 and text 4.5:1."
  echo "   Reach for a FOREGROUND role instead — controlIcon (>= 3:1 vs bg AND"
  echo "   surface), secondaryText (4.5:1), primaryText (7:1) — or, for a filled"
  echo "   control, the buttonFill/buttonLabel pair. See ResolvedPalette."
  exit 1
fi

echo "✅ PASS — no FILL role is drawn as a foreground."
