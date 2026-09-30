local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local bridge=slurp("safecardbridge.lua")
assert(bridge:find("cover_fetched = true",1,true))
assert(bridge:find("has_cover = false",1,true))
assert(bridge:find("function fake:extractInBackground() return false end",1,true))
assert(bridge:find("menu._do_cover_images = true",1,true))

local list=slurp("alreaderbooklist.lua")
assert(list:find('require("safecardbridge")',1,true))
assert(not list:find('require("coverbridge")',1,true))

local ui=slurp("libraryui.lua")
assert(ui:find("SERIES_SORT_STATE_VERSION = 2",1,true))
assert(ui:find("SERIES_SORT_REVERSE_KEY, false",1,true))
assert(ui:find("show series books SAFE CARD",1,true))
assert(ui:find("AlReaderBookList:new",1,true))

print("test_safe_card_bridge_static: PASS")
