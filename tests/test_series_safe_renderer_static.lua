local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end
local ui=slurp("libraryui.lua")
local bridge=slurp("safecardbridge.lua")
assert(ui:find("show series books SAFE CARD",1,true))
assert(ui:find("AlReaderBookList:new",1,true))
assert(bridge:find("extractInBackground() return false",1,true))
print("test_series_safe_renderer_static: PASS")
