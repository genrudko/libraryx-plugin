local DocumentRegistry = require("document/documentregistry")
local lfs = require("libs/libkoreader-lfs")
local Indexer = require("indexer")
local LibraryRepo = require("libraryrepo")
local ScanPlan = require("scanplan")

local Scanner = {}
Scanner.__index = Scanner

local function join(dir, name)
    if dir:sub(-1) == "/" then return dir .. name end
    return dir .. "/" .. name
end

local function walk(root, on_file, should_cancel)
    local function visit(dir)
        if should_cancel and should_cancel() then
            return false
        end
        local ok, iter, state = pcall(lfs.dir, dir)
        if not ok then
            return nil, iter
        end
        for name in iter, state do
            if name ~= "." and name ~= ".." then
                if should_cancel and should_cancel() then
                    return false
                end
                local path = join(dir, name)
                local attrs = lfs.attributes(path)
                if attrs then
                    if attrs.mode == "directory" then
                        local child_ok, child_err = visit(path)
                        if child_ok == nil then return nil, child_err end
                        if child_ok == false then return false end
                    elseif attrs.mode == "file" then
                        on_file(path, attrs)
                    end
                end
            end
        end
        return true
    end
    return visit(root)
end

function Scanner.new(ui, repo, indexer)
    repo = repo or LibraryRepo.new()
    return setmetatable({
        ui = assert(ui),
        repo = repo,
        indexer = indexer or Indexer.new(ui, repo),
    }, Scanner)
end

function Scanner:scanRoot(root_path, opts)
    opts = opts or {}
    local attrs = lfs.attributes(root_path)
    assert(attrs and attrs.mode == "directory", "scan root is not a directory: " .. tostring(root_path))

    local started_at = os.time()
    local token = self.repo:startScan(root_path, started_at)
    local stats = ScanPlan.newStats()
    local metadata_version = self.repo.getMetadataVersion
        and self.repo:getMetadataVersion() or 0
    local force_metadata_reindex = metadata_version < (Indexer.METADATA_VERSION or 1)

    local walk_ok, walk_err = walk(root_path, function(path, file_attrs)
        stats.visited = stats.visited + 1
        if not DocumentRegistry:hasProvider(path) then
            stats.unsupported = stats.unsupported + 1
            return
        end

        local fingerprint = not force_metadata_reindex
            and self.repo:getFingerprint(path) or nil
        if ScanPlan.sameFingerprint(fingerprint, file_attrs) then
            self.repo:touchUnchanged(
                path, file_attrs, token, started_at, self.indexer:readState(path))
            stats.unchanged = stats.unchanged + 1
        else
            local ok, result = pcall(self.indexer.indexFile, self.indexer,
                path, token, started_at)
            if ok and result then
                stats.indexed = stats.indexed + 1
            else
                stats.errors = stats.errors + 1
                if opts.on_error then
                    opts.on_error(path, ok and "index failed" or result)
                end
            end
        end

        if opts.on_progress then
            opts.on_progress(stats, path)
        end
    end, opts.should_cancel)

    if walk_ok == false then
        stats.cancelled = true
        return stats
    end
    if walk_ok == nil then
        stats.errors = stats.errors + 1
        if opts.on_error then opts.on_error(root_path, walk_err) end
        return stats
    end

    self.repo:finishScan(root_path, token, os.time())
    if force_metadata_reindex and self.repo.setMetadataVersion then
        self.repo:setMetadataVersion(Indexer.METADATA_VERSION or 1)
    end
    return stats
end

return Scanner
