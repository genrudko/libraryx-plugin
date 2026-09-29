#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
STAGE="$DIST/libraryx.koplugin"

rm -rf "$DIST"
mkdir -p "$STAGE/docs"

cp "$ROOT"/_meta.lua "$ROOT"/main.lua "$ROOT"/compat.lua \
   "$ROOT"/state.lua "$ROOT"/storage.lua "$ROOT"/model.lua "$ROOT"/libraryrepo.lua \
   "$ROOT"/indexer.lua "$ROOT"/scanplan.lua "$ROOT"/scanner.lua "$ROOT"/libraryxdebug.lua \
   "$ROOT"/debugui.lua "$ROOT"/libraryui.lua "$ROOT"/README.md "$STAGE"/
cp "$ROOT"/docs/*.md "$STAGE/docs"/

(
  cd "$DIST"
  zip -qr libraryx-debug.koplugin.zip libraryx.koplugin
)

echo "$DIST/libraryx-debug.koplugin.zip"
