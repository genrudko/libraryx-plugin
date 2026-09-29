local State = {}
State.__index = State

State.MODES = {
    start = true,
    authors = true,
    series = true,
    titles = true,
    books = true,
    genres = true,
    languages = true,
    scan_dates = true,
    file_dates = true,
    filters = true,
    folders = true,
    formats = true,
    recent = true,
    random = true,
    goto_author = true,
    goto_series = true,
    goto_folder = true,
}

local function clone_frame(frame)
    local out = {}
    for k, v in pairs(frame) do
        if type(v) == "table" then
            local t = {}
            for kk, vv in pairs(v) do t[kk] = vv end
            out[k] = t
        else
            out[k] = v
        end
    end
    return out
end

function State.new()
    return setmetatable({
        stack = {},
        current = {
            mode = "start",
            search = "",
            selected = nil,
            scroll_index = 1,
            page = 1,
            sort = "title",
            reverse = false,
            filters = {},
        },
    }, State)
end

function State:push(next_frame)
    assert(type(next_frame) == "table", "next_frame must be a table")
    assert(State.MODES[next_frame.mode], "unknown LibraryX mode: " .. tostring(next_frame.mode))
    self.stack[#self.stack + 1] = clone_frame(self.current)
    local frame = clone_frame(self.current)
    for k, v in pairs(next_frame) do frame[k] = v end
    self.current = frame
    return self.current
end

function State:back()
    if #self.stack == 0 then return nil end
    self.current = table.remove(self.stack)
    return self.current
end

function State:setScroll(index)
    assert(type(index) == "number" and index >= 1, "scroll index must be >= 1")
    self.current.scroll_index = math.floor(index)
end

function State:setSearch(text)
    self.current.search = text or ""
end

function State:setSort(sort_name, reverse)
    self.current.sort = assert(sort_name)
    self.current.reverse = reverse == true
end

return State
