local function slurp(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end
local repo=slurp("libraryrepo.lua")
for _,slug in ipairs({"to_read","read","later","worthy","trash","unknown"}) do
    assert(repo:find('slug="'..slug..'"',1,true))
end
assert(repo:find("function LibraryRepo:setFavorite",1,true))
assert(repo:find("function LibraryRepo:hasFavorite",1,true))
assert(repo:find("function LibraryRepo:listFavoriteBooks",1,true))
assert(repo:find("libraryx:favorite:",1,true))
local ui=slurp("libraryui.lua")
assert(ui:find("function LibraryUI:showFavoriteDialog",1,true))
assert(ui:find("function LibraryUI:showFavoritePicker",1,true))
assert(ui:find("function LibraryUI:showFavorites",1,true))
assert(slurp("main.lua"):find('ui:showFavorites("to_read")',1,true))
print("test_favorites_static: PASS")
