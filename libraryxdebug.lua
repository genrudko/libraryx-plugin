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

function Debug.clear()
    os.remove(path())
end

return Debug
