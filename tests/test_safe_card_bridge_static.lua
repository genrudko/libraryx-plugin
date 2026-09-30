local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local bridge=slurp("safecardbridge.lua")
assert(bridge:find('pcall(require, "bookinfomanager")',1,true))
assert(bridge:find("function adapter:getBookInfo(filepath, get_cover)",1,true))
assert(bridge:find("return real:getBookInfo(filepath, get_cover)",1,true))
assert(bridge:find("function adapter.isCachedCoverInvalid(bookinfo, cover_specs)",1,true))
assert(bridge:find("real.isCachedCoverInvalid, bookinfo, cover_specs",1,true))
assert(bridge:find("function adapter.getCachedCoverSize",1,true))
assert(bridge:find("real.getCachedCoverSize, img_w, img_h, max_img_w, max_img_h",1,true))
assert(bridge:find("function adapter:extractInBackground(files)",1,true))
assert(bridge:find("real.extractInBackground, real, files",1,true))
assert(bridge:find("menu._do_cover_images = true",1,true))
assert(not bridge:find("setmetatable(proxy",1,true))

local list=slurp("alreaderbooklist.lua")
assert(list:find('require("safecardbridge")',1,true))
assert(not list:find('require("coverbridge")',1,true))

local ui=slurp("libraryui.lua")
assert(ui:find("SERIES_SORT_STATE_VERSION = 2",1,true))
assert(ui:find("SERIES_SORT_REVERSE_KEY, false",1,true))
assert(ui:find("show series books SAFE CARD",1,true))
assert(ui:find("AlReaderBookList:new",1,true))

print("test_safe_card_bridge_static: PASS")
