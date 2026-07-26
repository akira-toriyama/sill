#!/usr/bin/env bash
#
# theme-env — a public themed widget must accept the AMBIENT theme, not only a
# prop-drilled one.
#
# WHY
# ---
# Before `.sillTheme(_:)` existed, every widget took `palette: ResolvedPalette`
# as a required init argument — 61 declarations across 25 files, with exactly
# ONE `@Environment` in all of Sources. That shape came from sill's only
# consumer being prism, which renders every catalog theme side by side and so
# genuinely wants per-widget override. A real app has one current theme and a
# deep view tree, and prop-drilling makes every intermediate view forward a
# palette it does not use.
#
# The fix was additive (explicit argument still wins), which is exactly why it
# needs a ratchet: nothing about adding a new widget forces the author to wire
# the environment, and a widget that misses it fails silently — it just quietly
# ignores the app's theme.
#
# THE RULE (no allow-list, so it cannot be bypassed by adding an entry):
# every `public struct … : View | NSViewRepresentable` in the SwiftUI modules
# that MENTIONS `ResolvedPalette` must also read `\.sillPalette`.
#
# A widget that takes no palette at all (the effect renderers, which are handed
# concrete colours) is out of scope and is not required to do anything.
#
# Usage: scripts/theme-env.sh [--list]
# Exit:  0 = every themed widget is ambient-aware · 1 = one is not · 2 = could not run.

set -euo pipefail
cd "$(dirname "$0")/.."

report() {
    python3 - "$1" <<'PY'
import pathlib, re, sys
mode = sys.argv[1]

ROOTS = ("Sources/ThemeKitUI", "Sources/MarkdownKitUI")
# `(?:<[^>]*>)?` is load-bearing: a generic view declares
# `public struct ThemedListView<ID: Hashable & Sendable>: View`, and a pattern
# demanding the colon right after the name silently skipped FIVE widgets while
# still reporting "all ambient-aware" — an under-counting gate is worse than no
# gate, because it reads as coverage.
DECL  = re.compile(r'^public struct (\w+)\s*(?:<[^>]*>)?\s*:[^{]*\b(?:View|NSViewRepresentable)\b', re.M)

rows = []
for root in ROOTS:
    for path in sorted(pathlib.Path(root).rglob("*.swift")):
        src = path.read_text(encoding="utf-8")
        rel = str(path).removeprefix("Sources/")
        for m in DECL.finditer(src):
            name = m.group(1)
            # The declaration's body: from this decl to the next top-level one.
            nxt = DECL.search(src, m.end())
            body = src[m.start(): nxt.start() if nxt else len(src)]
            themed  = "ResolvedPalette" in body
            ambient = "sillPalette" in body
            rows.append((rel, name, themed, ambient))

if mode == "--list":
    for rel, name, themed, ambient in rows:
        print(f"{'themed ' if themed else 'plain  '}{'amb' if ambient else '   '}  {name}  ({rel})")
    sys.exit(0)

bad = [(rel, name) for rel, name, themed, ambient in rows if themed and not ambient]
themed_n = sum(1 for r in rows if r[2])
if bad:
    print("theme-env: public themed widget ignores the ambient theme:", file=sys.stderr)
    for rel, name in bad:
        print(f"  + {name}  ({rel})", file=sys.stderr)
    print("""
  Add the three-tier resolution to the struct:

      @Environment(\\.sillPalette) private var ambientPalette
      private let explicitPalette: ResolvedPalette?
      var palette: ResolvedPalette { explicitPalette ?? ambientPalette ?? pal }

  and make the init argument `palette: ResolvedPalette? = nil`, assigning it to
  `explicitPalette`. Keep the argument — an explicit override must still win.
""", file=sys.stderr)
    sys.exit(1)

print(f"theme-env: ok — {themed_n} themed public widget(s), all ambient-aware.")
PY
}

report "${1:-}"
