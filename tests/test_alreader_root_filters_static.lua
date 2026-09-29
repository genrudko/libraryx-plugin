local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local ui=slurp("libraryui.lua")
for _, needle in ipairs({
    'L("all_books")',
    'L("authors")',
    'L("series")',
    'L("titles")',
    'L("folders")',
    'L("random_book")',
    'L("data_filters")',
    'L("scan_library")',
    'showLanguageFilter',
    'showGenreFilter',
    'showScanDateFilter',
    'showFileNoveltyFilter',
    'showAdditionalFilter',
    'showFormatFilter',
}) do
    assert(ui:find(needle,1,true), "missing AlReader root/filter contract: "..needle)
end

-- Service controls must not leak back into the visible catalog root.
local root_start=assert(ui:find("function LibraryUI:showRoot",1,true))
local root_body=ui:sub(root_start)
assert(not root_body:find('L("debug")',1,true))
assert(not root_body:find('L("library_folder")',1,true))

print("test_alreader_root_filters_static: PASS")
