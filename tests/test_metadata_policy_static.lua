local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local idx = slurp("indexer.lua")
assert(idx:find("has_real_metadata", 1, true))
assert(idx:find("self.ui.bookinfo:getDocProps(path)", 1, true))
assert(idx:find("Indexer.METADATA_VERSION", 1, true))

local scan = slurp("scanner.lua")
assert(scan:find("opts.force_reindex", 1, true))
assert(scan:find("metadata_current", 1, true))
assert(scan:find("setMetadataVersion", 1, true))

local ui = slurp("libraryui.lua")
assert(ui:find("showAlphabet", 1, true))
assert(ui:find("showSortDialog", 1, true))
assert(ui:find("sanitizeCardGenres", 1, true))
assert(ui:find("Settings.showGenres()", 1, true))
assert(ui:find("book.authors", 1, true))
assert(ui:find("book.genres", 1, true))

print("test_metadata_policy_static: PASS")
