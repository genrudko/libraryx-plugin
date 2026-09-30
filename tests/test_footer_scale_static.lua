local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local list=slurp("alreaderbooklist.lua")
for _, needle in ipairs({
    'libraryx_cards_per_page',
    'self.footer_prev = Button:new',
    'self.footer_next = Button:new',
    'self:onGotoPage(self.page - 1)',
    'self:onGotoPage(self.page + 1)',
    'text_font_size = 13',
    'table.insert(self.page_info, self.footer_prev)',
    'table.insert(self.page_info, self.footer_next)',
}) do
    assert(list:find(needle,1,true), "missing footer/scale contract: "..needle)
end

local bridge=slurp("safecardbridge.lua")
assert(bridge:find('libraryx_cards_per_page',1,true))
assert(not bridge:find('menu.files_per_page = 4',1,true))

local ui=slurp("libraryui.lua")
assert(ui:find("function LibraryUI:showListScaleDialog",1,true))
assert(ui:find('saveSetting("libraryx_cards_per_page", count)',1,true))
assert(ui:find('L("list_scale")',1,true))

print("test_footer_scale_static: PASS")
