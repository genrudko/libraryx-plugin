local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local list=slurp("alreaderbooklist.lua")
assert(list:find('function AlReaderBookList:showFooterMenu()',1,true))
assert(list:find('UIManager:nextTick(function()',1,true))
assert(list:find('self:showFooterMenu()',1,true))
assert(list:find('self.files_per_page = count',1,true))
assert(list:find('self:updateItems(1)',1,true))
assert(list:find('screen_w * 0.11',1,true))

local catalog=slurp("alreadercatalogmenu.lua")
assert(catalog:find('UIManager:nextTick(function()',1,true))
assert(catalog:find('L("menu_unavailable")',1,true))

print("test_footer_more_runtime_static: PASS")
