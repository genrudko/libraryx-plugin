local DataStorage = require("datastorage")

local Debug = {}
Debug.enabled = true

local function path()
    return DataStorage:getSettingsDir() .. "/libraryx-debug.log"
end

function Debug.path()
    return path()
end

function Debug.log(...)
    if not Debug.enabled then return end
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    local f = io.open(path(), "a")
    if not f then return end
    f:write(os.date("%Y-%m-%d %H:%M:%S"), " | ", table.concat(parts, " "), "\n")
    f:close()
end

function Debug.read()
    local f = io.open(path(), "r")
    if not f then return "(debug log is empty)" end
    local s = f:read("*a")
    f:close()
    return s ~= "" and s or "(debug log is empty)"
end

function Debug.readTail(max_bytes)
    max_bytes = max_bytes or 12000
    local f = io.open(path(), "r")
    if not f then return "(debug log is empty)" end
    local size = f:seek("end") or 0
    local start = math.max(0, size - max_bytes)
    f:seek("set", start)
    local data = f:read("*a") or ""
    f:close()
    if start > 0 then
        local first_newline = data:find("\n", 1, true)
        if first_newline then data = data:sub(first_newline + 1) end
    end
    return data ~= "" and data or "(debug log is empty)"
end

function Debug.clear()
    os.remove(path())
end

return Debug
