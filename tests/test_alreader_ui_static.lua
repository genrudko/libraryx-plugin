local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local bridge = slurp("coverbridge.lua")
assert(bridge:find("coverbrowser.koplugin/listmenu.lua", 1, true))
assert(bridge:find("_do_cover_images = true", 1, true))
assert(bridge:find("display_meta", 1, true))
assert(bridge:find("copy.has_meta = true", 1, true))

local list = slurp("alreaderbooklist.lua")
assert(list:find('right_icon = "appbar.search"', 1, true))
assert(list:find('text = "⋮"', 1, true))
assert(list:find('text = "×"', 1, true))
assert(list:find("files_per_page = 4", 1, true))
assert(list:find("util.stringLower", 1, true))
assert(not list:find("Menu.updatePageInfo", 1, true))
assert(list:find("WidgetContainer.clear(self.page_info, true)", 1, true))

local ui = slurp("libraryui.lua")
assert(ui:find('SORT_SERIES_INDEX = "series_index"', 1, true))
assert(ui:find("series_index", 1, true))
assert(ui:find("showAuthor", 1, true))
assert(ui:find('L("standalone_books")', 1, true))
assert(ui:find("AlReaderBookList:new", 1, true))
assert(ui:find("onSortTap", 1, true))
assert(ui:find("showBookActions", 1, true))
assert(ui:find("showGoTo", 1, true))
assert(ui:find("series_context = true", 1, true))

local repo = slurp("libraryrepo.lua")
assert(repo:find("CASE WHEN b.series_index IS NULL THEN 1 ELSE 0 END", 1, true))
assert(repo:find("authors=row[13]", 1, true))
assert(repo:find("b.reading_status, b.filemtime", 1, true))

print("test_alreader_ui_static: PASS")
