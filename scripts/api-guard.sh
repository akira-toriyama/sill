#!/usr/bin/env bash
#
# api-guard — a removal from sill's public surface must be RATED as a major.
#
# WHY THIS EXISTS
# ---------------
# Every consumer of sill pins `.upToNextMinor`. That pin excludes a new minor
# and a new major alike, so the bump LEVEL buys no automatic protection — it is
# purely the signal a human reads when they hand-bump their pin. A removal that
# ships rated as anything less than major is therefore invisible at exactly the
# moment someone is looking at it.
#
# That is not hypothetical. `catppuccin-latte` left the theme catalog in v1.36.0
# rated `:sparkles:` (minor) and broke wand at its next pin bump. CLAUDE.md
# writes the rule down — "Removing or renaming ANY public name => :boom: (or a
# trailing `!`) => MAJOR" — but prose does not fail a build. This does.
#
# WHAT IT CHECKS
#   1. Swift API surface, via `swift package diagnose-api-breaking-changes`
#      against the MERGE-BASE (not a tag: sill batches tags, so a tag baseline
#      would inherit other PRs' removals and blame this one for them).
#   2. `.library` product removals, which the API differ does NOT see — it
#      compares modules, and a product can be dropped while every module it
#      exported still exists.
#   3. The level this branch DECLARES, read from `glyph` — the same engine that
#      drives commit-lint and the release, so the gate can never disagree with
#      the release about what a commit means.
#
# The gate fails iff (1 or 2 found something) AND (3 is not `major`).
#
# KNOWN BLIND SPOT (do not mistake a green run for total safety): the API
# differ sees case IDENTIFIERS, not rawValue STRINGS. Renaming a `Theme` case's
# rawValue reports clean here — that channel's only guard is VocabularyTests.
#
# Usage:
#   scripts/api-guard.sh                 # baseline = merge-base with origin/main
#   scripts/api-guard.sh <treeish>       # explicit baseline
#
# Exit: 0 = ok · 1 = unrated removal · 2 = the gate itself could not run.

set -euo pipefail

cd "$(dirname "$0")/.."

ALLOWLIST=".api/breakage-allowlist.txt"

die() { printf 'api-guard: %s\n' "$*" >&2; exit 2; }

# --- baseline -------------------------------------------------------------
if [[ $# -ge 1 ]]; then
    BASE="$1"
else
    git rev-parse --verify --quiet origin/main >/dev/null \
        || die "no origin/main to take a merge-base from; pass a baseline explicitly"
    BASE="$(git merge-base origin/main HEAD)"
fi
git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null \
    || die "baseline '$BASE' is not a commit"
BASE="$(git rev-parse "$BASE")"

if [[ "$BASE" == "$(git rev-parse HEAD)" ]]; then
    echo "api-guard: baseline == HEAD, nothing to compare — ok"
    exit 0
fi

echo "api-guard: baseline $(git rev-parse --short "$BASE")  head $(git rev-parse --short HEAD)"

# --- 1. Swift API surface -------------------------------------------------
command -v swift >/dev/null || die "swift not on PATH"

apidiff_args=("$BASE")
if [[ -f "$ALLOWLIST" ]]; then
    # An allowlist with no stated reason is how a gate quietly stops gating.
    if ! grep -qE '^# rationale:' "$ALLOWLIST"; then
        die "$ALLOWLIST exists but has no '# rationale:' line — say why each entry is allowed"
    fi
    # `--breakage-allowlist-path` rejects an empty file, so only pass it along
    # once it actually carries an entry.
    if grep -qEv '^\s*(#.*)?$' "$ALLOWLIST"; then
        apidiff_args+=(--breakage-allowlist-path "$ALLOWLIST")
    fi
fi

echo "api-guard: diffing the Swift API surface (this builds both revisions)…"
apidiff_out="$(swift package diagnose-api-breaking-changes "${apidiff_args[@]}" 2>&1)" || true

# The differ reports each break on a `💔` line and exits non-zero; it also exits
# non-zero when it fails to build. Distinguish the two — a gate that reads a
# build failure as "no breaks" is worse than no gate.
if grep -q '💔' <<<"$apidiff_out"; then
    api_breaks="$(grep '💔' <<<"$apidiff_out" || true)"
elif grep -qE '^error: |Compiling for macOS.*failed|fatalError' <<<"$apidiff_out"; then
    printf '%s\n' "$apidiff_out" | tail -30 >&2
    die "the API differ failed to run (see above) — refusing to report a clean surface"
else
    api_breaks=""
fi

# --- 2. .library product removals ----------------------------------------
products_of() {
    # $1 = treeish, or "" for the working tree.
    if [[ -z "$1" ]]; then
        swift package dump-package
    else
        local wt
        wt="$(mktemp -d)"
        git worktree add --detach --quiet "$wt" "$1" || die "could not check out $1"
        # Point at the shared clone cache so this does not re-resolve the graph.
        (cd "$wt" && swift package dump-package) || die "dump-package failed at $1"
        git worktree remove --force "$wt" >/dev/null 2>&1 || true
    fi
}

extract_libs() {
    python3 -c '
import json,sys
pkg = json.load(sys.stdin)
for p in pkg.get("products", []):
    t = p.get("type", {})
    if "library" in t:
        print(p["name"])
' | sort
}

echo "api-guard: diffing .library products…"
base_libs="$(products_of "$BASE" | extract_libs)"
head_libs="$(products_of "" | extract_libs)"
removed_libs="$(comm -23 <(printf '%s\n' "$base_libs") <(printf '%s\n' "$head_libs") || true)"

# --- 3. the declared level ------------------------------------------------
command -v glyph >/dev/null || die "glyph not on PATH — the declared level is unreadable"
# `glyph bump` exits 1 on a `none` verdict (soft no-release) and still prints the
# JSON. Under `set -o pipefail` that non-zero would kill this assignment, so the
# exit code is deliberately discarded and the LEVEL is read from the payload.
glyph_json="$(glyph bump --range "$BASE..HEAD" --json 2>/dev/null || true)"
level="$(printf '%s' "$glyph_json" | python3 -c '
import json,sys
try:
    print(json.load(sys.stdin).get("level", "none"))
except Exception:
    print("none")
')"

# --- verdict --------------------------------------------------------------
# NB: written as `if` blocks, not `cond && assign`. Under `set -e` a trailing
# `&&` whose test is FALSE makes the whole line return 1 and kills the script —
# which silently turned this gate into an unconditional exit-1 until the
# red/green self-test caught it.
removed_anything=0
if [[ -n "$api_breaks" ]]; then removed_anything=1; fi
if [[ -n "$removed_libs" ]]; then removed_anything=1; fi

if [[ $removed_anything -eq 0 ]]; then
    echo "api-guard: no public removals — ok (declared level: $level)"
    exit 0
fi

echo
echo "api-guard: PUBLIC REMOVALS DETECTED"
if [[ -n "$api_breaks" ]]; then printf '%s\n' "$api_breaks" | sed 's/^/  /'; fi
if [[ -n "$removed_libs" ]]; then printf '  💔 .library product removed: %s\n' $removed_libs; fi
echo
echo "  declared level: $level"

if [[ "$level" == "major" ]]; then
    echo "api-guard: rated major — ok"
    exit 0
fi

cat >&2 <<EOF

api-guard: FAIL — this branch removes public API but declares "$level", not "major".

  Fix by RATING the removal truthfully: use :boom: (or a trailing ! on the
  subject) on the commit that does the removing.

  Do NOT reach for :fire: / :truck: / :coffin: — glyph rates all three
  "bump = none" AND keeps them out of the release notes, so they ship a break
  invisibly. That is exactly how catppuccin-latte left the catalog in v1.36.0
  and broke wand. Those three are for internal / dead / non-public code.

  If a removal is genuinely not a break for consumers, add it to $ALLOWLIST
  with a '# rationale:' line saying why.
EOF
exit 1
