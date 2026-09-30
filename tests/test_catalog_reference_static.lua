local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local catalog=slurp("alreadercatalogmenu.lua")
for _, needle in ipairs({
    'text = "⋮"',
    'text = "‹"',
    'text = "›"',
    'text = "×"',
    'footer_label',
    'onMoreTap',
    'onStatusTap',
    'right_icon = self.enable_search ~= false and "appbar.search" or nil',
    'left_icon = self.show_back ~= false and "chevron.left" or nil',
}) do
    assert(catalog:find(needle,1,true), "missing catalog shell: "..needle)
end

local ui=slurp("libraryui.lua")
for _, needle in ipairs({
    'function LibraryUI:showCatalogList',
    'function LibraryUI:showCatalogAlphabet',
    'function LibraryUI:showCatalogMore',
    'function LibraryUI:showTitles',
    'kind = "authors"',
    'kind = "series"',
    'kind = "folders"',
    'title = L("library")',
    'show_back = false',
    'show_more = false',
    'self:showBookDetails(book)',
}) do
    assert(ui:find(needle,1,true), "missing catalog reference behavior: "..needle)
end
assert(not ui:find("local menu = Menu:new",1,true))
assert(not ui:find("UIManager:show(AlReaderCatalogMenu:new",1,true))

print("test_catalog_reference_static: PASS")
