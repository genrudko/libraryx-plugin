local function slurp(path)
    local f=assert(io.open(path,'r')); local s=f:read('*a'); f:close(); return s
end
local ui=slurp('libraryui.lua')
local settings=slurp('libraryxsettingsui.lua')
assert(ui:find('local SettingsUI = require("libraryxsettingsui")',1,true), 'LibraryUI does not import settings UI')
assert(ui:find('name = L("settings")',1,true), 'settings row missing from Library root')
assert(ui:find('callback = function() SettingsUI.show() end',1,true), 'root settings callback missing')
assert(settings:find('function SettingsUI.show()',1,true), 'standalone settings screen missing')
assert(settings:find('TouchMenu:new{',1,true), 'standalone settings does not use TouchMenu')
assert(settings:find('local root = SettingsUI.menu()',1,true), 'standalone settings does not reuse settings definitions')
assert(settings:find('for _, item in ipairs(root.sub_item_table or {}) do',1,true), 'standalone settings does not reuse settings items')
print('test_root_settings_static: PASS')
