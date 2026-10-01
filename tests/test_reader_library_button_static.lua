local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local main = slurp("main.lua")
local ui = slurp("libraryui.lua")

assert(main:find('function LibraryX:_extendReaderMenuOrder()', 1, true))
assert(main:find('require, "ui/elements/reader_menu_order"', 1, true))
assert(main:find('if id == "filemanager" then', 1, true))
assert(main:find('table.insert(buttons, insert_at, "libraryx_reader")', 1, true))

assert(main:find('if self.ui.document then', 1, true))
assert(main:find('self:_extendReaderMenuOrder()', 1, true))
assert(main:find('self.ui.menu:registerToMainMenu(self)', 1, true))
assert(main:find('self.ui.menu.tab_item_table = nil', 1, true),
    'ReaderMenu cache must be invalidated after late plugin registration')

assert(main:find('menu_items.libraryx_reader = {', 1, true))
assert(main:find('icon = "book.opened"', 1, true))
assert(main:find('remember = false', 1, true))
assert(main:find('self.ui.menu:onTapCloseMenu()', 1, true))
assert(main:find('UIManager:nextTick(function()', 1, true))
assert(main:find('self:openLibrary()', 1, true))

assert(ui:find('show_back = self.plugin.ui and self.plugin.ui.document ~= nil', 1, true),
    'Reader-opened LibraryX root must expose a back affordance')

print("test_reader_library_button_static: PASS")
