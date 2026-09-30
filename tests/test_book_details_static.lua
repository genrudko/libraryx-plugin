local function slurp(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end

local repo=slurp("libraryrepo.lua")
assert(repo:find("function LibraryRepo:getBookDetails",1,true))
assert(repo:find("b.description",1,true))
assert(repo:find("b.directory",1,true))

local ui=slurp("libraryui.lua")
assert(ui:find('local BookDetails = require("libraryxbookdetails")',1,true))
assert(ui:find("function LibraryUI:showBookDetails",1,true))
assert(ui:find("bookinfo.getCoverImage",1,true))
assert(ui:find('on_favorites=function() self:showFavoriteDialog(full) end',1,true))
assert(ui:find('text=L("delete_book")',1,true))
assert(ui:find('text=L("favorites")',1,true))
assert(ui:find("util.splitToArray(book.authors",1,true))
assert(ui:find('mandatory = L("go_to_catalog")',1,true))

local details=slurp("libraryxbookdetails.lua")
assert(details:find("ScrollableContainer",1,true))
assert(details:find("ImageWidget",1,true))
assert(details:find('text = L("read_book")',1,true))
assert(details:find('text = L("favorites")',1,true))
assert(details:find('text = \"×\"',1,true))

print("test_book_details_static: PASS")
