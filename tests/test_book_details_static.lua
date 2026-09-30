local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local repo=slurp("libraryrepo.lua")
assert(repo:find("function LibraryRepo:getBookDetails",1,true))
assert(repo:find("b.description",1,true))
assert(repo:find("b.directory",1,true))

local ui=slurp("libraryui.lua")
assert(ui:find('local TextViewer = require("ui/widget/textviewer")',1,true))
assert(ui:find("function LibraryUI:showBookDetails",1,true))
assert(ui:find('text_format = "md"',1,true))
assert(ui:find('text = L("read_book")',1,true))
assert(ui:find('text = L("cover")',1,true))
assert(ui:find('text = L("go_to")',1,true))
assert(ui:find("self:showBookDetails(item.libraryx_book)",1,true))

print("test_book_details_static: PASS")
