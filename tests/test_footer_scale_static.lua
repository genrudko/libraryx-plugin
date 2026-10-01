local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local list=slurp("alreaderbooklist.lua")
for _, needle in ipairs({
    'Settings.get("list_density")',
    'Settings.set("list_density", value)',
    'self.footer_prev = Button:new',
    'self.footer_next = Button:new',
    'self:onGotoPage(self.page - 1)',
    'self:onGotoPage(self.page + 1)',
    'table.insert(self.page_info, self.footer_prev)',
    'table.insert(self.page_info, self.footer_next)',
}) do
    assert(list:find(needle,1,true), "missing footer/scale contract: "..needle)
end

local bridge=slurp("safecardbridge.lua")
assert(bridge:find('Settings.listDensity()',1,true))
assert(bridge:find('menu.files_per_page = nil',1,true))
assert(bridge:find('menu.files_per_page = menu.libraryx_target_rows',1,true))

local ui=slurp("libraryui.lua")
assert(ui:find("function LibraryUI:showListScaleDialog",1,true))
assert(ui:find('Settings.get("list_density")',1,true))
assert(ui:find('Settings.set("list_density", value)',1,true))
assert(ui:find('{ option(9), option(10) }',1,true))
assert(not ui:find('saveSetting("libraryx_cards_per_page"',1,true))

print("test_footer_scale_static: PASS")
