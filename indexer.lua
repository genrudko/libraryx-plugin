local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local ReadHistory = require("readhistory")
local lfs = require("libs/libkoreader-lfs")
local Model = require("model")
local LibraryRepo = require("libraryrepo")

local Indexer = {}
Indexer.__index = Indexer

local function history_map()
    local out = {}
    for _, item in ipairs(ReadHistory.hist or {}) do
        if item.file then
            out[item.file] = item.time
        end
    end
    return out
end

function Indexer.new(ui, repo)
    return setmetatable({
        ui = assert(ui),
        repo = repo or LibraryRepo.new(),
        history = history_map(),
    }, Indexer)
end

function Indexer:readState(path)
    local info = BookList.getBookInfo(path)
    return {
        status = BookList.getBookStatus(path),
        percent_finished = info and info.percent_finished or nil,
        last_read_at = self.history[path],
    }
end

function Indexer:indexFile(path, scan_token, scanned_at)
    if not DocumentRegistry:hasProvider(path) then
        return false, "unsupported"
    end
    local attrs = lfs.attributes(path)
    if not attrs or attrs.mode ~= "file" then
        return false, "missing"
    end

    local props = self.ui.bookinfo:getDocProps(path, nil, true)
    if not props or not next(props) then
        props = self.ui.bookinfo:getDocProps(path)
    end

    local read_state = self:readState(path)
    read_state.scan_token = scan_token
    local book = Model.bookRecord(path, attrs, props, read_state, scanned_at or os.time())
    self.repo:upsertBook(book)
    return true, book
end

return Indexer
