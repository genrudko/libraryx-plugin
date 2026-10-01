local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local repo=slurp("libraryrepo.lua")
assert(repo:find("b.reading_status, b.filemtime, b.added_at",1,true))
assert(not repo:find("b.reading_status, b.filemtime, b.filemtime",1,true))

local bridge=slurp("coverbridge.lua")
assert(bridge:find('type(value) == "function"',1,true))
assert(bridge:find("return value(real, ...)",1,true))

local list=slurp("alreaderbooklist.lua")
assert(list:find("booklist init begin",1,true))
assert(list:find("booklist initial render failed",1,true))

local ui=slurp("libraryui.lua")
assert(ui:find("function LibraryUI:_showBooks",1,true))
assert(ui:find("xpcall(function()",1,true))
assert(ui:find("author series selected",1,true))
assert(ui:find("self.repo:listBooksBySeries(series_name)",1,true))

print("test_author_series_crashguard_static: PASS")
