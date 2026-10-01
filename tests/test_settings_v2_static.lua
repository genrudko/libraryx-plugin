local function slurp(path)
    local f=assert(io.open(path,'r')); local s=f:read('*a'); f:close(); return s
end
local main=slurp('main.lua')
local ui=slurp('libraryui.lua')
local settings=slurp('libraryxsettingsui.lua')
local model=slurp('libraryxsettings.lua')
local icons=slurp('libraryxmenuicons.lua')
local meta=slurp('_meta.lua')
assert(main:find('libraryx_tab',1,true), 'dedicated KOReader LibraryX tab missing')
assert(main:find('LibraryX.MENU_ORDER',1,true), 'LibraryX tab order missing')
assert(main:find('_extendMenuOrder',1,true), 'menu-order injection missing')
assert(main:find('icon = "book.opened"',1,true), 'LibraryX top-tab icon missing')
for _, key in ipairs({'BOOK','USERS','SERIES','TITLES','FOLDER','RANDOM','FILTER','SETTINGS','REFRESH'}) do
    assert(ui:find('Icons.'..key,1,true), 'root icon missing: '..key)
end
for _, key in ipairs({'LIBRARY','LIST','PREVIEW','NAVIGATION','DATABASE','UPDATES','LANGUAGE','INFO'}) do
    assert(settings:find('Icons.'..key,1,true), 'settings section icon missing: '..key)
end
assert(settings:find('Updater.check',1,true), 'manual update check missing')
local p_library = assert(settings:find('Icons.LIBRARY',1,true))
local p_updates = assert(settings:find('Icons.UPDATES',p_library + 1,true))
local p_list = assert(settings:find('Icons.LIST',p_updates + 1,true))
assert(p_library < p_updates and p_updates < p_list,
    'Updates must be visible on the first Settings page immediately after Library')
assert(main:find('sorting_hint = "libraryx_tab"',1,true),
    'native Updates item needs LibraryX-tab orphan fallback')
assert(settings:find('update_auto_check',1,true), 'auto update check setting missing')
assert(settings:find('update_channel',1,true), 'update channel setting missing')
assert(model:find('scan_on_open',1,true), 'scan-on-open setting missing')
assert(model:find('show_alphabet',1,true), 'alphabet visibility setting missing')
assert(model:find('update_auto_check',1,true), 'auto update model setting missing')
assert(model:find('update_channel',1,true), 'update channel model setting missing')
assert(icons:find('function M.label',1,true), 'menu icon label helper missing')
assert(meta:find('version = "0.4.2-beta"',1,true), 'release version missing from metadata')
print('test_settings_v2_static: PASS')
