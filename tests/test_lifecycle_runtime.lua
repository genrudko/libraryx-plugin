package.path = './?.lua;' .. package.path

local shown = {}
local closed = {}
local scheduled = {}

package.loaded['ui/uimanager'] = {
    isWidgetShown = function(_, widget)
        return shown[widget] == true
    end,
    close = function(_, widget)
        closed[#closed + 1] = widget
        shown[widget] = false
    end,
    scheduleIn = function(_, delay, callback)
        scheduled[#scheduled + 1] = { delay = delay, callback = callback }
    end,
}

package.loaded['libraryxlifecycle'] = nil
local Lifecycle = require('libraryxlifecycle')

local w1, w2, w3 = {}, {}, {}
shown[w1] = true
shown[w2] = true
shown[w3] = false

assert(Lifecycle.track(w1) == w1)
assert(Lifecycle.track(w2) == w2)
assert(Lifecycle.track(w1) == w1) -- idempotent
assert(Lifecycle.track(w3) == w3)
assert(Lifecycle._trackedCount() == 3)

Lifecycle.closeAll()
assert(#closed == 2)
assert(closed[1] == w2, 'widgets must drain newest-first')
assert(closed[2] == w1, 'widgets must drain newest-first')
assert(Lifecycle._trackedCount() == 0)

assert(not Lifecycle.prepareReaderReturn())
assert(not Lifecycle.consumeClosePreservation())
Lifecycle.markReaderLaunch()
assert(Lifecycle.prepareReaderReturn())
assert(Lifecycle.consumeClosePreservation())
assert(not Lifecycle.consumeClosePreservation(), 'close preservation must be one-shot')

-- Reader -> Reader does not call prepareReaderReturn; provenance therefore
-- remains available for the eventual non-switch close.
Lifecycle.markReaderLaunch()
assert(Lifecycle.prepareReaderReturn())
assert(Lifecycle.consumeClosePreservation())

assert(not Lifecycle.isExiting())
Lifecycle.noteExit()
assert(Lifecycle.isExiting())
assert(#scheduled == 1 and scheduled[1].delay == 5)
scheduled[1].callback()
assert(not Lifecycle.isExiting(), 'exit backstop must clear a cancelled/stalled exit')

print('test_lifecycle_runtime: PASS')
