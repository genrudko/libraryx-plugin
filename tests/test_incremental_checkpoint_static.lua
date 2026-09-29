local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local storage = slurp("storage.lua")
assert(storage:find("metadata_version INTEGER NOT NULL DEFAULT 0", 1, true))
assert(storage:find("ALTER TABLE books ADD COLUMN metadata_version", 1, true))

local repo = slurp("libraryrepo.lua")
assert(repo:find("getFingerprintMap", 1, true))
assert(repo:find("adoptExistingRealMetadata", 1, true))
assert(repo:find("metadata_version=excluded.metadata_version", 1, true))

local scan = slurp("scanner.lua")
assert(scan:find("fingerprints[path]", 1, true))
assert(scan:find("metadata_current", 1, true))
assert(scan:find("opts.force_reindex", 1, true))
assert(not scan:find("force_metadata_reindex", 1, true))

local main = slurp("main.lua")
assert(main:find('L("update_library")', 1, true))
assert(main:find('L("full_rescan")', 1, true))

print("test_incremental_checkpoint_static: PASS")
