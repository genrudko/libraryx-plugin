local UIManager = require("ui/uimanager")

local Lifecycle = {}

-- LibraryX views are top-level UIManager widgets, not children of FileManager
-- or ReaderUI. Keep weak references so normal closes can still be collected,
-- but a KOReader exit can explicitly drain every LibraryX-owned layer.
local tracked = setmetatable({}, { __mode = "v" })
local seen = setmetatable({}, { __mode = "k" })
local tracked_max = 0
local exiting = false
local opened_from_libraryx = false
local preserve_next_close = false

function Lifecycle.track(widget)
    if not widget or seen[widget] then return widget end
    -- Reuse weak slots left by widgets that were closed and collected during
    -- this session; do not let the tracker grow forever on repeated opens.
    for i = 1, tracked_max do
        if tracked[i] == nil then
            tracked[i] = widget
            seen[widget] = true
            return widget
        end
    end
    tracked_max = tracked_max + 1
    tracked[tracked_max] = widget
    seen[widget] = true
    return widget
end

function Lifecycle.markReaderLaunch()
    opened_from_libraryx = true
end

function Lifecycle.prepareReaderReturn()
    local value = opened_from_libraryx
    opened_from_libraryx = false
    preserve_next_close = value == true
    return preserve_next_close
end

function Lifecycle.consumeClosePreservation()
    local value = preserve_next_close
    preserve_next_close = false
    return value
end

function Lifecycle.clearReaderReturn()
    opened_from_libraryx = false
    preserve_next_close = false
end

function Lifecycle.noteExit()
    exiting = true
    -- Backstop for an intercepted/cancelled exit path. A real exit terminates
    -- the event loop before this matters.
    if UIManager.scheduleIn then
        UIManager:scheduleIn(5, Lifecycle.clearExit)
    end
end

function Lifecycle.isExiting()
    return exiting
end

function Lifecycle.clearExit()
    exiting = false
end

function Lifecycle.closeAll()
    for i = tracked_max, 1, -1 do
        local widget = tracked[i]
        tracked[i] = nil
        if widget then
            seen[widget] = nil
            local shown = true
            if UIManager.isWidgetShown then
                local ok, value = pcall(UIManager.isWidgetShown, UIManager, widget)
                shown = ok and value == true
            end
            if shown and UIManager.close then
                pcall(UIManager.close, UIManager, widget)
            end
        end
    end
    tracked_max = 0
    opened_from_libraryx = false
    preserve_next_close = false
end

-- Test-only introspection; harmless in production and avoids exposing the
-- underlying weak tables.
function Lifecycle._trackedCount()
    local count = 0
    for i = 1, tracked_max do
        if tracked[i] then count = count + 1 end
    end
    return count
end

return Lifecycle
