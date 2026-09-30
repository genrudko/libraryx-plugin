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
    'title_bar_left_icon = "appbar.menu"',
    'subtitle = L("sort")',
}) do
    assert(ui:find(needle,1,true), "missing series sorting contract: "..needle)
end
print("test_series_sorting_static: PASS")
