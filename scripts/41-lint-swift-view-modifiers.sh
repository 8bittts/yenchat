#!/bin/bash
# SwiftUI bare-modifier lint
#
# Catches the silent self-recursion footgun where a SwiftUI view/shape modifier
# is written WITHOUT its leading dot, e.g.:
#
#     Rectangle()
#         .fill(Color.secondary)
#         .frame(width: w, height: h)
#         rotationEffect(.degrees(-45))   # <-- no dot
#
# A bare `rotationEffect(...)` inside a View body does NOT chain onto the
# preceding expression; it resolves to `self.rotationEffect(...)`, wrapping the
# WHOLE enclosing view. Inside an .overlay/.background closure that makes the
# view contain itself -> infinite SwiftUI metadata recursion -> stack overflow
# at render time. It compiles with zero warnings, so nothing else catches it.
# (Shipped latent in v1.073-v1.076 as the Cmd+Shift+B tab-sidebar crash.)
#
# Detection (precise, low false-positive): a line that, after indentation,
# starts with a known SwiftUI modifier name immediately followed by `(` and NO
# leading dot, where the previous non-blank/non-comment line ends a chain or
# closure (ends with `)` or `}`). Only files that `import SwiftUI` are scanned.
#
# Usage: ./scripts/41-lint-swift-view-modifiers.sh [SCAN_DIR]
#   SCAN_DIR defaults to yen-terminal/overlays/macos/Sources
# Exit: 0 clean, 1 violations found.
#
# Bash 3.2 / BSD coreutils compatible (no bash4 features, real grep/awk/find).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/gate-receipt.sh"
SCAN_DIR="${1:-$REPO_ROOT/yen-terminal/overlays/macos/Sources}"

# Fail-closed floor for the real overlay tree. Callers that pass an explicit
# SCAN_DIR (the fixture dirs in tests/125) are exempt, but the default scan must
# never silently shrink: a broken find, a moved Sources path, or a regressed
# import anchor would otherwise report "clean" over zero files. Current tree
# scans 60 SwiftUI files out of 155 Swift sources; the floor keeps headroom for
# ordinary churn while catching a collapse.
DEFAULT_SCAN=0
[ "$#" -eq 0 ] && DEFAULT_SCAN=1
MIN_DEFAULT_SCANNED="${YEN_VIEW_MODIFIER_LINT_MIN_SCANNED:-40}"

# Modifiers that are, in practice, only ever SwiftUI view/shape modifiers used
# as `.modifier(...)`. A bare occurrence is the bug, never legitimate.
MODIFIERS='rotationEffect|scaleEffect|rotation3DEffect|opacity|padding|frame|background|overlay|foregroundColor|foregroundStyle|font|offset|blur|shadow|clipShape|cornerRadius|border|mask|brightness|contrast|saturation|hueRotation|tint|fixedSize|aspectRatio|zIndex|blendMode|compositingGroup|animation|transition|disabled|hidden|accentColor|clipped|fill|stroke|strokeBorder|scaledToFit|scaledToFill|lineLimit|lineSpacing|multilineTextAlignment|truncationMode|textCase|underline|strikethrough|kerning|tracking|keyboardShortcut|contentShape'

if [ ! -d "$SCAN_DIR" ]; then
    echo "X SwiftUI bare-modifier lint: scan dir not found: $SCAN_DIR"
    exit 1
fi

HITS="$(mktemp -t yen-view-modifier-lint)"
lint_cleanup() { rm -f "$HITS"; }
gate_begin 41-lint-swift-view-modifiers lint_cleanup

FOUND=0
SCANNED=0

while IFS= read -r f; do
    [ -f "$f" ] || continue
    FOUND=$((FOUND + 1))
    # Precision: only lint SwiftUI files so non-UI free functions can't collide.
    # The anchor tolerates indentation (imports nested under `#if os(macOS)`) and
    # a leading attribute (`@preconcurrency import SwiftUI`); a bare `^import`
    # anchor silently skipped such files, which is how this gate lost coverage.
    grep -qE '^[[:space:]]*(@[A-Za-z_][A-Za-z0-9_]*[[:space:]]+)?import[[:space:]]+SwiftUI[[:space:]]*$' "$f" 2>/dev/null || continue
    SCANNED=$((SCANNED + 1))
    awk -v F="$f" -v mods="$MODIFIERS" '
        BEGIN { n = split(mods, M, "|"); for (i = 1; i <= n; i++) names[M[i]] = 1 }
        {
            t = $0
            sub(/^[ \t]+/, "", t)                       # strip leading indentation
            if (t == "" || substr(t, 1, 2) == "//" ||
                substr(t, 1, 1) == "*" || substr(t, 1, 2) == "/*") next   # skip blank/comments, keep prev
            if (match(t, /^[A-Za-z_][A-Za-z0-9_]*\(/)) {
                name = substr(t, 1, RLENGTH - 1)
                if ((name in names) && prev ~ /[)}],?$/) {
                    printf "%s:%d: %s\n", F, NR, $0
                }
            }
            prev = t
        }
    ' "$f" >> "$HITS"
done < <(find "$SCAN_DIR" -name '*.swift' -type f ! -path '*/Tests/*' 2>/dev/null || true)

COUNT="$(grep -c . "$HITS" 2>/dev/null || true)"
COUNT="${COUNT:-0}"

# An empty scan set is a broken gate, not a clean tree.
if [ "$FOUND" -eq 0 ]; then
    echo "X SwiftUI bare-modifier lint: no .swift files under $SCAN_DIR"
    echo "  Refusing to report clean over an empty scan set."
    gate_unit_skipped swift-scan "no .swift files under $SCAN_DIR"
    gate_unit_skipped bare-modifier-lint "not reached: empty scan set"
    gate_end 1
fi

if [ "$DEFAULT_SCAN" -eq 1 ] && [ "$SCANNED" -lt "$MIN_DEFAULT_SCANNED" ]; then
    echo "X SwiftUI bare-modifier lint: only $SCANNED SwiftUI file(s) scanned of $FOUND Swift source(s)."
    echo "  Expected at least $MIN_DEFAULT_SCANNED. The scan set collapsed --"
    echo "  check the Sources path and the 'import SwiftUI' anchor before trusting a clean run."
    gate_unit_skipped swift-scan "scan set collapsed to $SCANNED of $FOUND"
    gate_unit_skipped bare-modifier-lint "not reached: scan set collapsed"
    gate_end 1
fi

gate_unit_ran swift-scan "scanned=$SCANNED swift_sources=$FOUND"

if [ "$COUNT" -gt 0 ]; then
    echo "X SwiftUI bare-modifier lint: $COUNT violation(s)."
    echo "  A modifier is missing its leading '.' and silently binds to \`self\`"
    echo "  (infinite-recursion / stack-overflow risk at render):"
    echo ""
    while IFS= read -r line; do
        [ -n "$line" ] && echo "    $line"
    done < "$HITS"
    echo ""
    echo "  Fix: add the leading '.' so the modifier chains onto the preceding view."
    gate_unit_ran bare-modifier-lint "violations=$COUNT"
    gate_end 1
fi

echo "  ✓ SwiftUI bare-modifier lint clean ($(basename "$SCAN_DIR"); scanned $SCANNED SwiftUI of $FOUND Swift file(s))"
gate_unit_ran bare-modifier-lint "scanned=$SCANNED violations=$COUNT"
gate_end 0
