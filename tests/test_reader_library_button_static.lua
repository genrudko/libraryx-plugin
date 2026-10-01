local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local main = slurp("main.lua")
local ui = slurp("libraryui.lua")
local i18n = slurp("libraryxi18n.lua")

assert(main:find('function LibraryX:_extendReaderMenuOrder()', 1, true))
assert(main:find('require, "ui/elements/reader_menu_order"', 1, true))
assert(main:find('if id == "filemanager" then', 1, true))
assert(main:find('table.insert(buttons, insert_at, "libraryx_reader")', 1, true))
assert(main:find('order.libraryx_reader = LibraryX.MENU_ORDER', 1, true),
    'Reader tab must use the same LibraryX submenu order as FileManager')

assert(main:find('self:_extendReaderMenuOrder()', 1, true))
assert(main:find('self.ui.menu:registerToMainMenu(self)', 1, true))
assert(main:find('self.ui.menu.tab_item_table = nil', 1, true),
    'ReaderMenu cache must be invalidated after late plugin registration')

assert(main:find('local parent_id = in_reader and "libraryx_reader" or "libraryx_tab"', 1, true))
assert(main:find('menu_items[parent_id] = {', 1, true))

for _, id in ipairs({
    'libraryx_open',
    'libraryx_last_book',
    'libraryx_favorites',
    'libraryx_folder',
    'libraryx_scan',
    'libraryx_settings',
    'libraryx_updates',
    'libraryx_about',
    'libraryx_debug',
}) do
    assert(main:find('menu_items.' .. id .. ' = {', 1, true),
        'shared LibraryX menu item missing: ' .. id)
    assert(main:find('"' .. id .. '"', 1, true),
        'LibraryX.MENU_ORDER missing: ' .. id)
end

assert(main:find('function LibraryX:getLastBookPath()', 1, true))
assert(main:find('readSetting("lastfile")', 1, true))
assert(main:find('lfs.attributes(path, "mode") ~= "file"', 1, true))
assert(main:find('function LibraryX:openLastBook(from_menu)', 1, true))
assert(main:find('self.ui.document.file == path', 1, true))
assert(main:find('require("apps/reader/readerui"):showReader(path)', 1, true))

assert(ui:find('name = L("open_last_book")', 1, true),
    'LibraryX root must expose Open last book')
assert(ui:find('self.plugin:openLastBook(self.plugin.library_menu)', 1, true))
assert(ui:find('show_back = self.plugin.ui and self.plugin.ui.document ~= nil', 1, true),
    'Reader-opened LibraryX root must expose a back affordance')

assert(i18n:find('open_last_book = "Open last book"', 1, true))
assert(i18n:find('open_last_book = "Открыть последнюю книгу"', 1, true))
assert(i18n:find('last_book_unavailable', 1, true))

print("test_reader_library_button_static: PASS")
