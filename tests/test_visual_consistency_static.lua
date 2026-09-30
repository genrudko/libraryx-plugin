local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end
local bridge=slurp("safecardbridge.lua")
assert(bridge:find('fixed_item_font_size" then return true',1,true))

local list=slurp("alreaderbooklist.lua")
assert(list:find('"%s · %d-%d"',1,true))
assert(list:find("text_font_size = 11",1,true))

local ui=slurp("libraryui.lua")
assert(ui:find('require("alreadercatalogmenu")',1,true))
assert(not ui:find("UIManager:show(Menu:new{",1,true))

local catalog=slurp("alreadercatalogmenu.lua")
assert(catalog:find('left_icon = "chevron.left"',1,true))
assert(catalog:find('right_icon = self.enable_search ~= false and "appbar.search" or nil',1,true))
assert(catalog:find('text = "×"',1,true))
assert(catalog:find('self.footer_prev',1,true))
assert(catalog:find('self.footer_next',1,true))

print("test_visual_consistency_static: PASS")
