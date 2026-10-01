#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="$DIST/libraryx.koplugin"

rm -rf "$DIST"
mkdir -p "$STAGE/docs"

# Every top-level Lua file is a runtime module of the plugin. Copy them as a
# set instead of maintaining a second hand-written manifest: a newly required
# module must never be able to pass source tests and then disappear from ZIP.
cp "$ROOT"/*.lua "$STAGE"/
cp "$ROOT"/README.md "$STAGE"/
cp "$ROOT"/docs/*.md "$STAGE/docs"/

# Fail closed if the staged runtime module set differs from the source tree.
diff -u \
  <(cd "$ROOT" && find . -maxdepth 1 -type f -name '*.lua' -printf '%f\n' | sort) \
  <(cd "$STAGE" && find . -maxdepth 1 -type f -name '*.lua' -printf '%f\n' | sort)

(
  cd "$DIST"
  zip -qr libraryx-debug.koplugin.zip libraryx.koplugin
)

echo "$DIST/libraryx-debug.koplugin.zip"
