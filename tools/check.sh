#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/4] repository layout"
test -f _meta.lua
test -f main.lua
test -f compat.lua
test -f state.lua
test -f storage.lua
test -f model.lua
test -f libraryrepo.lua
test -f indexer.lua
test -f scanplan.lua
test -f scanner.lua
test -f libraryui.lua
test -f debugui.lua
test -f libraryxdebug.lua
test -f libraryxi18n.lua

LOCAL_LJ="$(find "$PWD/.tools/luajit" -type f -path '*/bin/luajit*' 2>/dev/null | head -n1 || true)"
LOCAL_LIBDIR="$(find "$PWD/.tools/luajit" -type f -name 'libluajit-5.1.so.2*' -printf '%h\n' 2>/dev/null | head -n1 || true)"

if command -v luajit >/dev/null 2>&1; then
  LUA_BIN="$(command -v luajit)"
elif [[ -n "$LOCAL_LJ" ]]; then
  LUA_BIN="$LOCAL_LJ"
  export LD_LIBRARY_PATH="$LOCAL_LIBDIR"
elif command -v lua >/dev/null 2>&1; then
  LUA_BIN="$(command -v lua)"
else
  LUA_BIN=""
fi

echo "[2/4] Lua syntax"
if [[ -n "$LUA_BIN" ]]; then
  for f in _meta.lua main.lua compat.lua state.lua storage.lua model.lua libraryrepo.lua indexer.lua scanplan.lua scanner.lua libraryxdebug.lua libraryxi18n.lua debugui.lua libraryui.lua tests/test_state.lua tests/test_model.lua tests/test_scanplan.lua tests/test_scanner.lua tests/test_no_rows_api.lua tests/test_debug_build_static.lua tests/test_device_bugfix_static.lua; do
    "$LUA_BIN" -e "local chunk, err = loadfile([[$f]]) if not chunk then error(err) end"
    echo "syntax OK: $f"
  done
else
  echo "SKIP: no Lua runtime available"
fi

echo "[3/4] pure-Lua state test"
if [[ -n "$LUA_BIN" ]]; then
  "$LUA_BIN" tests/test_state.lua
  "$LUA_BIN" tests/test_model.lua
  "$LUA_BIN" tests/test_scanplan.lua
  "$LUA_BIN" tests/test_scanner.lua
  "$LUA_BIN" tests/test_no_rows_api.lua tests/test_debug_build_static.lua tests/test_device_bugfix_static.lua
else
  echo "SKIP: no Lua runtime available"
fi

echo "[4/4] prohibited generated artifacts"
if find . -maxdepth 2 \( -name '*.sqlite3' -o -name '*.sqlite3-wal' -o -name '*.sqlite3-shm' \) -print -quit | grep -q .; then
  echo "Unexpected SQLite artifact in repository" >&2
  exit 1
fi

echo "LibraryX checks: PASS"
