#!/usr/bin/env bash
#
# appkit-floor — the 3-floor AppKit policy, machine-enforced.
#
# THE POLICY (CLAUDE.md, 確定 2026-06-23 / 更新 2026-06-30)
# --------------------------------------------------------
# The widget layer is SwiftUI by default. AppKit is permitted on exactly THREE
# floors — the places SwiftUI genuinely cannot reach:
#
#   floor 1  IME (Japanese input) core — NSTextField's field editor: detecting
#            marked text, and routing Enter/Esc/↑↓ differently while a
#            conversion is uncommitted. The EDIT CORE only; frame, label, icon,
#            colours and error state are SwiftUI.
#   floor 2  A window that floats without stealing focus, and a popup that
#            escapes its parent window — `.nonactivatingPanel`. The window
#            SHELL only; the contents go through NSHostingView and are SwiftUI.
#   floor 3  Selectable rich text (markdown) — continuous selection + copy,
#            the rounded inline-code pill (NSLayoutManager
#            fillBackgroundRectArray), and real NSTextTable tables/code
#            blocks/blockquote rules. SwiftUI's Text/textRenderer is mutually
#            exclusive with .textSelection (proved in prism, 2026-06-30). The
#            NSTextView DRAW CORE only.
#
# Anything else in AppKit requires asking the user first (要相談). That rule
# lived only in prose, so nothing stopped the debt from growing — this script is
# the ratchet that does.
#
# HOW IT RATCHETS
# ---------------
# The allow-list below is compared for SET EQUALITY, not "no new entries". So:
#   * a NEW unlisted AppKit construct fails the gate  (debt cannot grow)
#   * a STALE entry whose code is gone ALSO fails      (debt must be booked out)
# Every migration PR therefore deletes its own line, and the list can only
# shrink. Entries tagged DEBT are the ones a future PR is expected to remove.
#
# READ THIS BEFORE TRUSTING A GREEN RUN: green means the debt did not GROW. It
# does NOT mean the policy is satisfied — 14 of the 16 entries below are DEBT.
# Only two are real floors: the IME field editor and the markdown draw core.
#
# Usage: scripts/appkit-floor.sh [--list]
# Exit:  0 = matches the allow-list · 1 = drifted · 2 = the gate could not run.

set -euo pipefail

cd "$(dirname "$0")/.."

# --- the allow-list: "<file>:<construct>  # floor N | DEBT" ----------------
# Sorted. Keep the trailing comment — it is the only place a reader learns
# WHICH floor justifies an entry, or that it is debt awaiting migration.
read -r -d '' ALLOWED <<'EOF' || true
MarkdownKitUI/MarkdownTextView.swift:NSViewRepresentable        # floor 3 — the selectable rich-text draw core
ThemeKitUI/ThemedButtonGroupView.swift:NSViewRepresentable      # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedButtonView.swift:NSViewRepresentable           # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedCheckboxView.swift:NSViewRepresentable         # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedChipView.swift:NSViewRepresentable             # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedComboBoxView.swift:NSViewRepresentable         # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedDividerView.swift:NSViewRepresentable          # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedFABView.swift:NSViewRepresentable              # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedMenuTriggerView.swift:NSViewRepresentable      # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedSkeletonView.swift:NSViewRepresentable         # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedTextFieldView.swift:NSViewRepresentable        # floor 1 — the IME field-editor core
ThemeKitUI/ThemedToolBarView.swift:NSViewRepresentable          # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedTooltipAnchorView.swift:NSViewRepresentable    # DEBT — should be SwiftUI-native
ThemeKitUI/ThemedTooltip.swift:CAShapeLayer                     # DEBT — bubble CONTENT in CALayer, past the floor-2 shell
ThemeKitUI/ThemedTooltip.swift:CATextLayer                      # DEBT — bubble CONTENT in CALayer, past the floor-2 shell
ThemeKitUI/ThemedTooltip.swift:CALayer                          # DEBT — bubble CONTENT in CALayer, past the floor-2 shell
EOF

# --- scan ------------------------------------------------------------------
# Only DECLARATION sites count, so a comment mentioning NSViewRepresentable (as
# AnimatedBorderView.swift and ThemedListView.swift both do) is not booked as
# debt. Likewise CALayer is counted at CONSTRUCTION (`CALayer()`), not where a
# view merely touches `.layer` — PopupPanel legitimately animates the shell's
# layer under floor 2.
scan() {
    python3 - <<'PY'
import pathlib, re, sys

ROOTS = ("Sources/ThemeKitUI", "Sources/MarkdownKitUI")

# A conformance DECLARATION, not a mention. `\b` is unavailable in BSD sed, and
# the shell-quoting of this regex was itself a portability bug once — keeping
# the scan in python removes both hazards.
DECL = re.compile(r"^\s*(?:public\s+|private\s+|internal\s+|final\s+)*"
                  r"(?:struct|class)\s+\w+\s*:[^{]*\bNSViewRepresentable\b")
# CALayer & friends at CONSTRUCTION — `.layer` access is not a widget drawing
# itself in Core Animation.
CTOR = re.compile(r"\b(CALayer|CAShapeLayer|CATextLayer|CAGradientLayer|NSVisualEffectView)\s*\(\s*\)")

out = set()
for root in ROOTS:
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        rel = str(path).removeprefix("Sources/")
        # PopupPanel IS the floor-2 window shell; animating the shell's own
        # layer is what floor 2 permits, so it is not counted.
        shell = path.name == "PopupPanel.swift"
        for line in path.read_text(encoding="utf-8").splitlines():
            stripped = line.lstrip()
            if stripped.startswith("//"):
                continue
            if DECL.search(line):
                out.add(f"{rel}:NSViewRepresentable")
            if not shell:
                for m in CTOR.finditer(line):
                    out.add(f"{rel}:{m.group(1)}")

print("\n".join(sorted(out)))
PY
}

allow_keys() {
    printf '%s\n' "$ALLOWED" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//' \
        | grep -vE '^\s*$' | sort -u
}

found="$(scan)"
allowed="$(allow_keys)"

if [[ "${1:-}" == "--list" ]]; then
    printf '%s\n' "$found"
    exit 0
fi

new="$(comm -23 <(printf '%s\n' "$found") <(printf '%s\n' "$allowed") || true)"
stale="$(comm -13 <(printf '%s\n' "$found") <(printf '%s\n' "$allowed") || true)"

status=0
if [[ -n "$new" ]]; then
    status=1
    echo "appkit-floor: NEW AppKit construct outside the 3 permitted floors:" >&2
    printf '  + %s\n' $new >&2
    cat >&2 <<'EOF'

  AppKit is permitted ONLY for: (1) the IME field-editor core, (2) the
  nonactivating-panel window shell, (3) the selectable rich-text draw core.
  Build it in SwiftUI, or — if you believe SwiftUI genuinely cannot do it —
  ASK THE USER FIRST (要相談). Do not widen the floors unilaterally.

  If it IS floor-justified, add it to the allow-list in this script with the
  floor number and the reason.
EOF
fi

if [[ -n "$stale" ]]; then
    status=1
    echo "appkit-floor: STALE allow-list entry — the code is gone, book it out:" >&2
    printf '  - %s\n' $stale >&2
    echo >&2
    echo "  Delete these lines from the allow-list in $0." >&2
fi

if [[ $status -eq 0 ]]; then
    debt="$(printf '%s\n' "$ALLOWED" | grep -c '# DEBT' || true)"
    total="$(printf '%s\n' "$allowed" | grep -c . || true)"
    echo "appkit-floor: ok — $total AppKit construct(s), $debt still DEBT."
    echo "appkit-floor: green means the debt did NOT GROW, not that the policy is met."
fi
exit $status
