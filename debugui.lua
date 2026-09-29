local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local LibraryRepo = require("libraryrepo")
local Debug = require("libraryxdebug")
local L = require("libraryxi18n").t

local DebugUI = {}

function DebugUI.report(plugin)
    local repo = LibraryRepo.new()
    local root = plugin:getLibraryRoot() or "(not selected)"
    local text = table.concat({
        "LibraryX debug",
        "",
        "root: " .. root,
        "books: " .. tostring(repo:countBooks()),
        "authors: " .. tostring(repo:countAuthors()),
        "series: " .. tostring(repo:countSeries()),
        "database: " .. tostring(repo.storage.path),
        "log: " .. Debug.path(),
        "",
        "--- log ---",
        Debug.read(),
    }, "\n")
    UIManager:show(TextViewer:new{
        title = L("debug_title"),
        text = text,
    })
end

return DebugUI
