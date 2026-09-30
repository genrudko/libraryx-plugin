local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local ui=slurp("libraryui.lua")
for _, needle in ipairs({
    'SERIES_SORT_KEY',
    'SERIES_SORT_REVERSE_KEY',
    'getSeriesSortMode',
    'getSeriesSortReverse',
    'showSeriesSortDialog',
    'SORT_SERIES_INDEX',
    'SORT_TITLE',
    'SORT_AUTHOR',
    'SORT_ADDED',
    'SORT_FILEDATE',
}) do
    assert(ui:find(needle,1,true), "missing series sorting contract: "..needle)
end
assert(ui:find("SERIES_SORT_STATE_VERSION = 2",1,true))
assert(ui:find("SERIES_SORT_REVERSE_KEY, false",1,true))
print("test_series_sorting_static: PASS")
