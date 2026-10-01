#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/4] repository layout"
required=(
  _meta.lua main.lua compat.lua state.lua storage.lua model.lua libraryrepo.lua
  indexer.lua scanplan.lua scanner.lua libraryui.lua libraryxbookdetails.lua
  alreaderbooklist.lua alreadercatalogmenu.lua coverbridge.lua safecardbridge.lua
  debugui.lua libraryxdebug.lua libraryxi18n.lua libraryxsettings.lua
  libraryxsettingsui.lua libraryxkoreadermenu.lua libraryxmenuicons.lua
  libraryxhttp.lua libraryxupdater.lua
)
for f in "${required[@]}"; do
  test -f "$f" || { echo "Missing required file: $f" >&2; exit 1; }
done

LOCAL_LJ="$(find "$PWD/.tools/luajit" -type f -path '*/bin/luajit*' 2>/dev/null | head -n1 || true)"
LOCAL_LIBDIR="$(find "$PWD/.tools/luajit" -type f -name 'libluajit-5.1.so.2*' -printf '%h\n' 2>/dev/null | head -n1 || true)"

if command -v luajit >/dev/null 2>&1; then
  LUA_BIN="$(command -v luajit)"
elif [[ -n "$LOCAL_LJ" ]]; then
  LUA_BIN="$LOCAL_LJ"
  export LD_LIBRARY_PATH="$LOCAL_LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
elif command -v lua >/dev/null 2>&1; then
  LUA_BIN="$(command -v lua)"
else
  echo "ERROR: Lua/LuaJIT runtime is required; refusing to report PASS with tests skipped." >&2
  exit 1
fi
echo "Lua runtime: $("$LUA_BIN" -v 2>&1 | head -n1)"

mapfile -t lua_files < <(find . -maxdepth 2 -type f -name '*.lua' -not -path './dist/*' | sort)

echo "[2/4] Lua syntax (${#lua_files[@]} files)"
for f in "${lua_files[@]}"; do
  "$LUA_BIN" -e "local chunk, err = loadfile([[$f]]) if not chunk then error(err) end"
done

mapfile -t tests < <(find tests -maxdepth 1 -type f -name '*.lua' | sort)
echo "[3/4] tests (${#tests[@]} files)"
for t in "${tests[@]}"; do
  echo "RUN $t"
  "$LUA_BIN" "$t"
done

echo "[4/4] prohibited generated artifacts"
if find . -maxdepth 2 \( -name '*.sqlite3' -o -name '*.sqlite3-wal' -o -name '*.sqlite3-shm' \) -print -quit | grep -q .; then
  echo "Unexpected SQLite artifact in repository" >&2
  exit 1
fi

echo "LibraryX checks: PASS"
