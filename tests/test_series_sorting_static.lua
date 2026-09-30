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
assert(ui:find('AlReaderBookList:new',1,true), "missing series card renderer: AlReaderBookList:new")
assert(ui:find('libraryx_display_metadata = display_meta',1,true), "missing series card renderer: libraryx_display_metadata = display_meta")
assert(ui:find('series_context = true',1,true), "missing series card renderer: series_context = true")
assert(ui:find('onSortTap = function()',1,true), "missing series card renderer: onSortTap = function()")
assert(ui:find('showSeriesSortDialog(menu, title, books, mode, reverse)',1,true), "missing series card renderer: showSeriesSortDialog(menu, title, books, mode, reverse)")
print("test_series_sorting_static: PASS")
