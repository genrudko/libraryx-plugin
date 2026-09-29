local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local storage = slurp("storage.lua")
assert(storage:find("SCHEMA_VERSION = 4", 1, true))
assert(storage:find("added_at INTEGER", 1, true))
assert(storage:find("ALTER TABLE books ADD COLUMN added_at INTEGER", 1, true))
assert(storage:find("added_at=scanned_at", 1, true))

local repo = slurp("libraryrepo.lua")
assert(repo:find("metadata_version, added_at, title", 1, true))
-- Critical: ON CONFLICT must not reset added_at on every incremental scan.
assert(not repo:find("added_at=excluded.added_at", 1, true))
assert(repo:find("b.reading_status, b.filemtime, b.added_at", 1, true))

print("test_added_at_static: PASS")
