local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local list=slurp("alreaderbooklist.lua")
for _, needle in ipairs({
    'title_face = Font:getFace("x_smalltfont")',
    'title_shrink_font_to_fit = true',
    'subtitle = title_parent',
    'self.footer_alpha = Button:new',
    'L("alphabet_short")',
    'L("page_of")',
    'footer more tapped',
    'safeAction("footer more"',
}) do
    assert(list:find(needle,1,true), "missing book-list fix: "..needle)
end
assert(not list:find('"%s · %d-%d"',1,true))

local catalog=slurp("alreadercatalogmenu.lua")
for _, needle in ipairs({
    'title_face = Font:getFace("x_smalltfont")',
    'title_shrink_font_to_fit = true',
    'self.footer_alpha = Button:new',
    'L("page_of")',
}) do
    assert(catalog:find(needle,1,true), "missing catalog fix: "..needle)
end

local ui=slurp("libraryui.lua")
assert(ui:find("onAlphabetTap =",1,true))
assert(ui:find("self:showAlphabet(menu, books, mode)",1,true))
assert(ui:find("self:showCatalogAlphabet(menu, rows)",1,true))

print("test_footer_alphabet_title_static: PASS")
