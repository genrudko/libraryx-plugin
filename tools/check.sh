#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/4] repository layout"
test -f _meta.lua
test -f main.lua
test -f compat.lua
test -f state.lua
test -f storage.lua

echo "[2/4] Lua syntax"
if command -v luac >/dev/null 2>&1; then
  for f in _meta.lua main.lua compat.lua state.lua storage.lua tests/test_state.lua; do
    luac -p "$f"
  done
elif command -v luajit >/dev/null 2>&1; then
  for f in _meta.lua main.lua compat.lua state.lua storage.lua tests/test_state.lua; do
    luajit -b "$f" /tmp/libraryx-check.out
  done
  rm -f /tmp/libraryx-check.out
else
  echo "SKIP: no luac/luajit available"
fi

echo "[3/4] pure-Lua state test"
if command -v lua >/dev/null 2>&1; then
  lua tests/test_state.lua
elif command -v luajit >/dev/null 2>&1; then
  luajit tests/test_state.lua
else
  echo "SKIP: no Lua runtime available"
fi

echo "[4/4] prohibited generated artifacts"
if find . -maxdepth 2 \( -name '*.sqlite3' -o -name '*.sqlite3-wal' -o -name '*.sqlite3-shm' \) -print -quit | grep -q .; then
  echo "Unexpected SQLite artifact in repository" >&2
  exit 1
fi

echo "LibraryX checks: PASS"
