local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local ui=slurp("libraryui.lua")
local a=assert(ui:find("function LibraryUI:showSeriesBooks",1,true))
local b=assert(ui:find("function LibraryUI:showAuthor",a,true))
local body=ui:sub(a,b)

assert(body:find("Menu:new",1,true))
assert(body:find("SORT_SERIES_INDEX",1,true))
assert(body:find("multilines_forced = true",1,true))
assert(body:find("show series books SAFE",1,true))
assert(not body:find("AlReaderBookList:new",1,true))
assert(not body:find("CoverBridge",1,true))

print("test_series_safe_renderer_static: PASS")
