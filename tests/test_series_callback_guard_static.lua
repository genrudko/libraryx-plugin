local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local ui=slurp("libraryui.lua")
assert(ui:find("function LibraryUI:guardedAction",1,true))
assert(ui:find("function LibraryUI:openSeries",1,true))
assert(ui:find('self.repo:listBooksBySeries(series_name)',1,true))
assert(ui:find('self:openSeries(',1,true))
assert(ui:find("series_context = false",1,true))

local repo=slurp("libraryrepo.lua")
local a=assert(repo:find("function LibraryRepo:listBooksBySeries",1,true))
local b=assert(repo:find("function LibraryRepo:listBooksByFolder",a,true))
local body=repo:sub(a,b)
assert(body:find("FROM books",1,true))
assert(body:find("author_stmt",1,true))
assert(body:find("genre_stmt",1,true))
assert(not body:find("group_concat",1,true))

local dbg=slurp("libraryxdebug.lua")
assert(dbg:find("function Debug.readTail",1,true))

print("test_series_callback_guard_static: PASS")
