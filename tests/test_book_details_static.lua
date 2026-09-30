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
assert(ui:find('local BOOK_DETAILS_TEXT_TYPE = "libraryx_book_info"',1,true))
assert(ui:find("BOOK_DETAILS_FONT_SIZE = 20",1,true))
assert(ui:find("font-family: 'Noto Sans', sans-serif",1,true))
assert(ui:find('title_face = Font:getFace("x_smalltfont")',1,true))
assert(ui:find('text_format = "html"',1,true))
assert(ui:find("text_type = BOOK_DETAILS_TEXT_TYPE",1,true))
assert(ui:find('text = L("read_book")',1,true))
assert(ui:find('text = L("cover")',1,true))
assert(ui:find('text = L("go_to")',1,true))
assert(ui:find("self:showBookDetails(item.libraryx_book)",1,true))

print("test_book_details_static: PASS")
