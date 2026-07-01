#!/usr/bin/env bash
# Run the XCTest suite locally with a full Xcode toolchain.
#
# The maintainer's shell defaults to CommandLineTools, which ships no XCTest, so a
# plain `swift test` fails to link. Xcode is installed but not `xcode-select`ed.
# This wrapper points DEVELOPER_DIR at a full Xcode and builds into an ISOLATED
# path (.build-xcode/) so the Xcode/Swift-6.3 test artifacts never clobber the
# CLT `.build/` that `swift build` uses — mixing toolchains in one build dir
# breaks the next CommandLineTools `swift build`.
#
# Usage:
#   scripts/test.sh                          # run the whole suite
#   scripts/test.sh --filter PaletteTests    # forwards any `swift test` args
#   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/test.sh  # pin an Xcode
set -euo pipefail
cd "$(dirname "$0")/.."

# Resolve a full Xcode: honor an explicit DEVELOPER_DIR, else pick the newest /Applications/Xcode*.app.
dev="${DEVELOPER_DIR:-}"
if [[ -z "$dev" || ! -x "$dev/usr/bin/xcodebuild" ]]; then
  dev=""
  for app in /Applications/Xcode*.app; do
    [[ -x "$app/Contents/Developer/usr/bin/xcodebuild" ]] && dev="$app/Contents/Developer"
  done
fi
if [[ -z "$dev" ]]; then
  echo "scripts/test.sh: no full Xcode found under /Applications (CommandLineTools alone can't run XCTest)." >&2
  echo "  Install Xcode and retry, or set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer." >&2
  echo "  Tests otherwise run in CI (.github/workflows/build.yml)." >&2
  exit 1
fi

echo "scripts/test.sh: swift test via ${dev}" >&2
exec env DEVELOPER_DIR="$dev" swift test --build-path .build-xcode "$@"
