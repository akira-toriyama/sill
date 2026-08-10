#!/usr/bin/env bash
#
# interaction-alphas — hover / pressed / focus / disabled alphas live in ONE
# place (`PaletteKit`), not inline in each widget.
#
# WHY
# ---
# This was a rule-of-three violation INSIDE sill, needing no consumer app to
# justify it. Before `stateOverlay(_:on:)` landed, the contained pair
# (pressed 0.12 / hover 0.08) was written out verbatim in ThemedButton,
# ThemedChip and ThemedFAB; the transparent pair (pressed 0.16 / hover-or-focus
# 0.06) in ThemedButton and ThemedChip; and the outlined resting stroke
# (role@0.5) in ThemedButton, ThemedChip and ThemedButtonGroup. Fifteen sites,
# one concept. Centralising them is only half the job — this is the half that
# keeps them centralised.
#
# WHAT IS *NOT* AN INTERACTION ALPHA
# ----------------------------------
# The allow-list below is not debt. Each entry is a genuinely different concept
# that merely shares a number, and forcing it through `stateOverlay` would be
# wrong:
#   * a drop-target affordance (DnD, not pointer state)
#   * a badge/tint backing
#   * a shimmer gradient stop
#   * a RESTING cell fill (no interaction involved)
# Read an entry before "fixing" it.
#
# Set-equality, like scripts/appkit-floor.sh: a NEW inline alpha fails, and a
# STALE entry whose code is gone also fails.
#
# Usage: scripts/interaction-alphas.sh [--list]
# Exit:  0 = matches · 1 = drifted · 2 = could not run.

set -euo pipefail
cd "$(dirname "$0")/.."

read -r -d '' ALLOWED <<'EOF' || true
ThemeKitUI/ThemedGridView.swift:0.08          # resting cell fill — no interaction
ThemeKitUI/ThemedListRow.swift:0.12           # DnD drop-target wash — not pointer state
ThemeKitUI/ThemedGridView.swift:0.12          # DnD drop-target wash — the grid twin of the list ring (t-n3be)
ThemeKitUI/ThemedListRow.swift:0.16           # badge/tint backing pair
ThemeKitUI/ThemedThumbnailCell.swift:0.12     # shimmer gradient stop
EOF

scan() {
    python3 - <<'PY'
import pathlib, re

ROOTS = ("Sources/ThemeKit", "Sources/ThemeKitUI")

# Two patterns, deliberately NOT one.
#
# `withAlphaComponent` is the AppKit widget idiom, and 0.5 there IS the
# outlined resting stroke this centralised — so it is in scope.
#
# `.opacity` is SwiftUI's general-purpose dimming and 0.5 there is NOT a
# state token: it appears as a glow/shadow alpha (ThemedPillView's matched
# shadow, ThemedGridView's stroke). Flagging bare `.opacity(0.5)` would report
# shadows as interaction debt, which is how a lint teaches people to ignore it.
APPKIT  = re.compile(r"withAlphaComponent\(\s*0\.(06|08|12|16|5|50)\s*\)")
SWIFTUI = re.compile(r"\.opacity\(\s*0\.(06|08|12|16)\s*\)")

def norm(frac):
    return "0.5" if frac in ("5", "50") else f"0.{frac}"

out = set()
for root in ROOTS:
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        rel = str(path).removeprefix("Sources/")
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.lstrip().startswith("//"):
                continue
            for pat in (APPKIT, SWIFTUI):
                for m in pat.finditer(line):
                    out.add(f"{rel}:{norm(m.group(1))}")
print("\n".join(sorted(out)))
PY
}

allow_keys() {
    printf '%s\n' "$ALLOWED" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//' \
        | grep -vE '^\s*$' | sort -u
}

found="$(scan)"; allowed="$(allow_keys)"
if [[ "${1:-}" == "--list" ]]; then printf '%s\n' "$found"; exit 0; fi

new="$(comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$allowed") || true)"
stale="$(comm -13 <(printf '%s\n' "$found") <(printf '%s\n' "$allowed") || true)"

status=0
if [[ -n "$new" ]]; then
    status=1
    echo "interaction-alphas: inline interaction alpha outside PaletteKit:" >&2
    printf '  + %s\n' $new >&2
    cat >&2 <<'EOF'

  Route it through the shared accessor instead:
    palette.stateOverlay(.hover|.pressed|.focus, on: .contrastInk(on: fill) | .roleTint(colour))
    palette.restingStroke(of: roleColour)
    palette.disabledInk / .disabledFill / .disabledStroke

  If it is genuinely a DIFFERENT concept that happens to share the number
  (a drop affordance, a gradient stop, a resting fill), add it to the
  allow-list in this script WITH the reason.
EOF
fi
if [[ -n "$stale" ]]; then
    status=1
    echo "interaction-alphas: stale allow-list entry — the code is gone:" >&2
    printf '  - %s\n' $stale >&2
    echo "  Delete these lines from the allow-list in $0." >&2
fi
if [[ $status -eq 0 ]]; then
    echo "interaction-alphas: ok — $(printf '%s\n' "$allowed" | grep -c .) non-interaction exception(s), no inline state alphas."
fi
exit $status
