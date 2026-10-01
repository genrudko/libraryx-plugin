local function slurp(path)
    local f = assert(io.open(path, 'r'))
    local s = f:read('*a')
    f:close()
    return s
end

local main = slurp('main.lua')
local ui = slurp('libraryui.lua')
local settings = slurp('libraryxsettingsui.lua')
local updater = slurp('libraryxupdater.lua')
local check = slurp('tools/check.sh')

assert(main:find('local Lifecycle = require("libraryxlifecycle")', 1, true))
assert(main:find('function LibraryX:onExit()', 1, true))
assert(main:find('LibraryX.onRestart = LibraryX.onExit', 1, true))
assert(main:find('function LibraryX:onCloseDocument()', 1, true))
assert(main:find('Lifecycle.prepareReaderReturn()', 1, true))
assert(main:find('function LibraryX:onCloseWidget()', 1, true))
assert(main:find('self.ui.tearing_down and not Lifecycle.isExiting()', 1, true))
assert(main:find('Lifecycle.consumeClosePreservation()', 1, true))
assert(main:find('Lifecycle.closeAll()', 1, true))

assert(ui:find('Lifecycle.markReaderLaunch()', 1, true))
local _, launch_count = ui:gsub('Lifecycle%.markReaderLaunch%(%s*%)', '')
assert(launch_count == 2, 'both LibraryX reader launch paths must mark provenance')
local _, track_count = ui:gsub('Lifecycle%.track%(', '')
assert(track_count >= 5, 'all persistent LibraryX views must be lifecycle-tracked')

assert(settings:find('Lifecycle.track(menu)', 1, true))
assert(updater:find('Lifecycle.track(viewer)', 1, true))
assert(updater:find('Lifecycle.track(confirm)', 1, true))
assert(check:find('libraryxlifecycle.lua', 1, true))

print('test_lifecycle_integration_static: PASS')
