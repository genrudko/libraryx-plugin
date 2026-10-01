local saved = {}
G_reader_settings = {
    readSetting = function(_, key, default)
        local v = saved[key]
        if v == nil then return default end
        return v
    end,
    saveSetting = function(_, key, value) saved[key] = value end,
    delSetting = function(_, key) saved[key] = nil end,
    flush = function() end,
    has = function(_, key) return saved[key] ~= nil end,
}

package.path = './?.lua;' .. package.path
local Settings = require('libraryxsettings')

assert(Settings.get('list_density') == 'auto')
assert(Settings.get('list_font_scale') == 100)
assert(Settings.get('details_body_scale') == 90)
assert(Settings.get('details_title_scale') == 100)
assert(Settings.get('details_cover_scale') == 100)
assert(Settings.get('list_show_genres') == true)
assert(Settings.get('details_show_path') == true)
assert(Settings.showAlphabet() == true)
assert(Settings.scanOnOpen() == false)
assert(Settings.autoUpdateCheck() == true)
assert(Settings.updateChannel() == 'beta')

Settings.set('list_density', 9)
assert(Settings.get('list_density') == 9)
Settings.set('list_font_scale', 500)
assert(Settings.get('list_font_scale') == 120)
Settings.set('details_body_scale', 10)
assert(Settings.get('details_body_scale') == 70)
Settings.set('language', 'ru')
Settings.set('update_channel', 'stable')
assert(Settings.updateChannel() == 'stable')
assert(Settings.get('language') == 'ru')
Settings.resetAll()
assert(Settings.get('list_density') == 'auto')
assert(Settings.get('language') == 'system')
print('test_settings_runtime: PASS')
