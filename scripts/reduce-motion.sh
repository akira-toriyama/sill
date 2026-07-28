#!/usr/bin/env bash
#
# reduce-motion — a library file that DRIVES an animation must honour the
# system's Reduce Motion setting.
#
# WHY
# ---
# "Reduce Motion" is not a preference about taste; for a person with vestibular
# sensitivity it is the difference between using the machine and not. sill is
# where the family's motion lives — particle bursts, ink splatter, orbiting line
# pets, a chomp corridor, a repeating shimmer — so every app inherits whatever
# sill decides here, and none of them can opt out on their user's behalf.
#
# The shape of the bug this catches is silence. `AnimatedBorderView` read
# `@Environment(\.accessibilityReduceMotion)` and rested its rim on a steady
# hue; the six sibling effect views, written the same week against the same
# `frozen:` still-frame mechanism, simply never asked. Nothing failed, nothing
# warned, and the difference was invisible in review because the compliant file
# and the violating file look identical until you grep for one identifier.
#
# THE RULE
# --------
# Strip comments and string literals, then: a file under Sources/ that names an
# animation DRIVER (`TimelineView`, `withAnimation`, `.animation(`,
# `NSAnimationContext`, `.animator()`, a `CA*Animation`, `repeatForever`) must
# also name a reduce-motion signal (`accessibilityReduceMotion` or
# `accessibilityDisplayShouldReduceMotion`) — or appear in the allow-list below
# with a stated reason.
#
# Stripping comments is load-bearing, not tidiness: `PaletteKit/
# AnimatedPalette.swift` contains the word `TimelineView` only inside a prose
# comment pointing at the gallery. A naive grep reports it as a violating file
# forever, and a gate that cries wolf is a gate someone deletes.
#
# SCOPE — file level, deliberately. A struct-level scan (what `theme-env.sh`
# does) would be more precise but would MISS the drivers that do not live in a
# `public struct … : View` at all: `WindowShell`'s panel fade and
# `ThemedTooltip`'s NSWorkspace check both sit in helper types. Under-counting
# is the one failure mode this family of gates must not have, so this one takes
# the coarser unit and says so. `Sources/prism` is excluded: it is the demo app,
# whose entire job is to run every effect at once for inspection.
#
# The allow-list is compared for SET EQUALITY, not "no new entries". A file that
# starts honouring reduce-motion must be REMOVED from the list, or the gate
# fails — an allow-list nobody prunes is a list nobody reads.
#
# Usage: scripts/reduce-motion.sh [--list]
# Exit:  0 = every animating file honours reduce-motion (or is allowed)
#        1 = drifted · 2 = the gate could not run.

set -euo pipefail
cd "$(dirname "$0")/.."

# --- the allow-list: "<file>  # reason" ------------------------------------
# NOT debt. A crossfade is what macOS itself SUBSTITUTES when Reduce Motion is
# on (System Settings > Accessibility > Display), so an opacity fade is the
# accessible answer, not a violation of it. If WindowShell ever animates
# position or scale, it leaves this list.
read -r -d '' ALLOWED <<'EOF' || true
ThemeKit/WindowShell.swift    # opacity-only panel crossfade — the substitution macOS itself makes under Reduce Motion
EOF

scan() {
    python3 - <<'PY'
import pathlib, re, sys

# Drivers: something here starts a clock or an implicit animation.
DRIVERS = re.compile(
    r'TimelineView|withAnimation\s*\(|\.animation\s*\(|NSAnimationContext'
    r'|\.animator\s*\(\s*\)|CA(?:Basic|Keyframe|Spring)?Animation|repeatForever')
# Signals: something here asks the system whether motion is wanted.
SIGNALS = re.compile(r'accessibilityReduceMotion|accessibilityDisplayShouldReduceMotion')

def code_only(src: str) -> str:
    """Source with string literals and comments removed.

    Literals go FIRST so that a `//` inside a string (a URL) cannot be read as
    the start of a comment, and so that the word `TimelineView` inside a
    docstring-ish literal cannot register as a driver."""
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', ' ', src)
    src = re.sub(r'//[^\n]*', '', src)
    return src

rows, scanned = [], 0
for path in sorted(pathlib.Path("Sources").rglob("*.swift")):
    rel = str(path).removeprefix("Sources/")
    if rel.startswith("prism/"):
        continue
    scanned += 1
    code = code_only(path.read_text(encoding="utf-8"))
    drivers = sorted(set(m.group(0).rstrip("( ") for m in DRIVERS.finditer(code)))
    if not drivers:
        continue
    rows.append((rel, drivers, bool(SIGNALS.search(code))))

# stdout: the machine channel (violating files). stderr: the census, so the
# caller can always see HOW MANY files were looked at — a gate that reports
# only "ok" cannot be told apart from a gate whose pattern stopped matching.
print(f"reduce-motion: scanned {scanned} file(s), "
      f"{len(rows)} animate, {sum(1 for r in rows if r[2])} honour reduce-motion",
      file=sys.stderr)
for rel, drivers, ok in rows:
    if not ok:
        print(rel)
PY
}

listing() {
    python3 - <<'PY'
import pathlib, re
DRIVERS = re.compile(
    r'TimelineView|withAnimation\s*\(|\.animation\s*\(|NSAnimationContext'
    r'|\.animator\s*\(\s*\)|CA(?:Basic|Keyframe|Spring)?Animation|repeatForever')
SIGNALS = re.compile(r'accessibilityReduceMotion|accessibilityDisplayShouldReduceMotion')

def code_only(src):
    src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
    src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
    src = re.sub(r'/\*(?:.|\n)*?\*/', ' ', src)
    return re.sub(r'//[^\n]*', '', src)

for path in sorted(pathlib.Path("Sources").rglob("*.swift")):
    rel = str(path).removeprefix("Sources/")
    if rel.startswith("prism/"):
        continue
    code = code_only(path.read_text(encoding="utf-8"))
    drivers = sorted(set(m.group(0).rstrip("( ") for m in DRIVERS.finditer(code)))
    if drivers:
        print(f"{'ok  ' if SIGNALS.search(code) else 'MISS'}  {rel}  [{', '.join(drivers)}]")
PY
}

allow_keys() {
    printf '%s\n' "$ALLOWED" | sed -E 's/[[:space:]]*#.*$//; s/[[:space:]]+$//' \
        | sed '/^$/d' | sort
}

if [ "${1:-}" = "--list" ]; then listing; exit 0; fi

found="$(scan | sort)"
allowed="$(allow_keys)"

new="$(comm -23 <(printf '%s\n' "$found" | sed '/^$/d') <(printf '%s\n' "$allowed") || true)"
stale="$(comm -13 <(printf '%s\n' "$found" | sed '/^$/d') <(printf '%s\n' "$allowed") || true)"

status=0
if [ -n "$new" ]; then
    status=1
    {
        echo "reduce-motion: this file drives an animation but never asks about Reduce Motion:"
        printf '  + %s\n' $new
        cat <<'HINT'

  A SwiftUI view reads the environment and collapses to a still frame:

      @Environment(\.accessibilityReduceMotion) private var reduceMotion

  The six effect views already have the mechanism — their `frozen: Double?`
  branch renders one static frame — so honouring it is `frozen ?? (reduceMotion
  ? Self.reduceMotionFrame : nil)`, not new rendering code.

  An AppKit type reads it live, because the user can flip it while the app runs:

      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

  If the animation is opacity-ONLY, it is already the accessible substitution —
  add it to the allow-list in this script WITH that reason.
HINT
    } >&2
fi
if [ -n "$stale" ]; then
    status=1
    {
        echo "reduce-motion: stale allow-list entry — this file now honours reduce-motion:"
        printf '  - %s\n' $stale
        echo "  Delete these lines from the allow-list in $0."
    } >&2
fi

[ "$status" -eq 0 ] && echo "reduce-motion: ok — every animating file honours reduce-motion or is allowed."
exit "$status"
