local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

for _, path in ipairs({"main.lua", "debugui.lua", "libraryui.lua"}) do
    local src = slurp(path)
    assert(not src:find('require%("debug"%)'), path .. " collides with Lua standard debug module")
end

local repo = slurp("libraryrepo.lua")
assert(repo:find("local row = stmt:step%(%)"), "row iteration must use stmt:step() return value")
assert(not repo:find("stmt:step%(row%)"), "unsupported stmt:step(row) usage")

local main = slurp("main.lua")
assert(main:find('require%("ui/trapper"%)'), "debug build scan must use Trapper")
assert(main:find("Trapper:info"), "scan must expose cooperative progress/cancel")
assert(main:find("stats.cancelled"), "scan cancellation result must be handled")

print("test_debug_build_static: PASS")
