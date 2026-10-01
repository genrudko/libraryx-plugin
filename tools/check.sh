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
test -f libraryxbookdetails.lua
test -f alreaderbooklist.lua
test -f alreadercatalogmenu.lua
test -f coverbridge.lua
test -f safecardbridge.lua
test -f debugui.lua
test -f libraryxdebug.lua
test -f libraryxi18n.lua
test -f libraryxsettings.lua
test -f libraryxsettingsui.lua
test -f libraryxkoreadermenu.lua

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
  for f in _meta.lua main.lua compat.lua state.lua storage.lua model.lua libraryrepo.lua indexer.lua scanplan.lua scanner.lua libraryxdebug.lua libraryxi18n.lua libraryxsettings.lua libraryxsettingsui.lua libraryxkoreadermenu.lua debugui.lua coverbridge.lua safecardbridge.lua alreaderbooklist.lua alreadercatalogmenu.lua libraryui.lua libraryxbookdetails.lua tests/test_state.lua tests/test_model.lua tests/test_scanplan.lua tests/test_scanner.lua tests/test_no_rows_api.lua tests/test_debug_build_static.lua tests/test_device_bugfix_static.lua tests/test_metadata_policy_static.lua tests/test_incremental_checkpoint_static.lua tests/test_alreader_ui_static.lua tests/test_added_at_static.lua tests/test_alreader_root_filters_static.lua tests/test_author_series_crashguard_static.lua tests/test_series_callback_guard_static.lua tests/test_series_sorting_static.lua tests/test_safe_card_bridge_static.lua tests/test_book_details_static.lua tests/test_footer_scale_static.lua tests/test_visual_consistency_static.lua tests/test_catalog_reference_static.lua tests/test_footer_alphabet_title_static.lua tests/test_footer_more_runtime_static.lua tests/test_footer_hitbox_static.lua tests/test_density_scaling_static.lua tests/test_adaptive_cards_static.lua tests/test_background_index_scaling_static.lua tests/test_series_safe_renderer_static.lua tests/test_favorites_static.lua tests/test_start_with_static.lua tests/test_i18n_static.lua tests/test_settings_runtime.lua tests/test_settings_integration_static.lua tests/test_root_settings_static.lua tests/test_koreader_topmenu_static.lua; do
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
  "$LUA_BIN" tests/test_no_rows_api.lua tests/test_debug_build_static.lua tests/test_device_bugfix_static.lua tests/test_metadata_policy_static.lua tests/test_incremental_checkpoint_static.lua tests/test_alreader_ui_static.lua tests/test_added_at_static.lua tests/test_alreader_root_filters_static.lua tests/test_author_series_crashguard_static.lua tests/test_series_callback_guard_static.lua tests/test_series_sorting_static.lua tests/test_safe_card_bridge_static.lua tests/test_book_details_static.lua tests/test_footer_scale_static.lua tests/test_visual_consistency_static.lua tests/test_catalog_reference_static.lua tests/test_footer_alphabet_title_static.lua tests/test_footer_more_runtime_static.lua tests/test_footer_hitbox_static.lua tests/test_density_scaling_static.lua tests/test_adaptive_cards_static.lua tests/test_series_safe_renderer_static.lua
  "$LUA_BIN" tests/test_density_scaling_static.lua
  "$LUA_BIN" tests/test_adaptive_cards_static.lua
  "$LUA_BIN" tests/test_background_index_scaling_static.lua
  "$LUA_BIN" tests/test_i18n_static.lua
  "$LUA_BIN" tests/test_settings_runtime.lua
  "$LUA_BIN" tests/test_settings_integration_static.lua
  "$LUA_BIN" tests/test_root_settings_static.lua
  "$LUA_BIN" tests/test_koreader_topmenu_static.lua
else
  echo "SKIP: no Lua runtime available"
fi

echo "[4/4] prohibited generated artifacts"
if find . -maxdepth 2 \( -name '*.sqlite3' -o -name '*.sqlite3-wal' -o -name '*.sqlite3-shm' \) -print -quit | grep -q .; then
  echo "Unexpected SQLite artifact in repository" >&2
  exit 1
fi

echo "LibraryX checks: PASS"
