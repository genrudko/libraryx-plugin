package.path = "./?.lua;" .. package.path

local tree = {
    ["/root"] = { "new.fb2", "same.epub", "note.txt", "sub" },
    ["/root/sub"] = { "changed.fb2" },
}
local attrs = {
    ["/root"] = { mode = "directory" },
    ["/root/sub"] = { mode = "directory" },
    ["/root/new.fb2"] = { mode = "file", size = 10, modification = 1 },
    ["/root/same.epub"] = { mode = "file", size = 20, modification = 2 },
    ["/root/note.txt"] = { mode = "file", size = 5, modification = 3 },
    ["/root/sub/changed.fb2"] = { mode = "file", size = 31, modification = 4 },
}

package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path) return attrs[path] end,
        dir = function(path)
            local list = assert(tree[path], "unknown directory " .. path)
            local i = 0
            return function()
                i = i + 1
                return list[i]
            end
        end,
    }
end

package.preload["document/documentregistry"] = function()
    return {
        hasProvider = function(_, path)
            return path:match("%.fb2$") or path:match("%.epub$")
        end,
    }
end

package.preload["indexer"] = function() return { METADATA_VERSION = 2, new = function() error("not used") end } end
package.preload["libraryrepo"] = function() return { new = function() error("not used") end } end

local Scanner = require("scanner")

local touched, indexed = {}, {}
local finished
local repo = {
    startScan = function(_, root_path, started_at)
        assert(root_path == "/root")
        assert(type(started_at) == "number")
        return 7
    end,
    getMetadataVersion = function() return 2 end,
    setMetadataVersion = function(_, version) assert(version == 2) end,
    getFingerprint = function(_, path)
        if path == "/root/same.epub" then
            return { filesize = 20, filemtime = 2, metadata_version = 2 }
        elseif path == "/root/sub/changed.fb2" then
            return { filesize = 30, filemtime = 4, metadata_version = 2 }
        end
    end,
    getFingerprintMap = function(self)
        return {
            ["/root/same.epub"] = { filesize = 20, filemtime = 2, metadata_version = 2 },
            ["/root/sub/changed.fb2"] = { filesize = 30, filemtime = 4, metadata_version = 2 },
        }
    end,
    adoptExistingRealMetadata = function() end,
    touchUnchanged = function(_, path, file_attrs, token)
        assert(token == 7)
        touched[#touched + 1] = path
    end,
    finishScan = function(_, root_path, token, finished_at)
        finished = { root_path, token, finished_at }
    end,
}
local indexer = {
    readState = function(_, path)
        return { status = "reading", percent_finished = 0.5, last_read_at = 123 }
    end,
    indexFile = function(_, path, token, scanned_at)
        assert(token == 7)
        assert(type(scanned_at) == "number")
        indexed[#indexed + 1] = path
        return true, { path = path }
    end,
}

local scanner = Scanner.new({}, repo, indexer)
local progress = 0
local stats = scanner:scanRoot("/root", {
    on_progress = function(s, path)
        progress = progress + 1
        assert(type(path) == "string")
        assert(s.visited >= progress)
    end,
})

assert(stats.visited == 4)
assert(stats.indexed == 2)
assert(stats.unchanged == 1)
assert(stats.unsupported == 1)
assert(stats.errors == 0)
assert(stats.cancelled == false)
assert(progress == 3) -- callback only after supported files are processed
assert(#touched == 1 and touched[1] == "/root/same.epub")
table.sort(indexed)
assert(indexed[1] == "/root/new.fb2")
assert(indexed[2] == "/root/sub/changed.fb2")
assert(finished and finished[1] == "/root" and finished[2] == 7)

-- Cancellation must not deactivate unseen books.
finished = nil
local calls = 0
local cancelled = scanner:scanRoot("/root", {
    should_cancel = function()
        calls = calls + 1
        return calls >= 2
    end,
})
assert(cancelled.cancelled == true)
assert(finished == nil)

print("test_scanner: PASS")
