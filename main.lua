local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LibraryRepo = require("libraryrepo")
local LibraryUI = require("libraryui")
local Scanner = require("scanner")
local Debug = require("debug")
local DebugUI = require("debugui")
local _ = require("gettext")

local ROOT_KEY = "libraryx_library_root"

local LibraryX = WidgetContainer:extend{
    name = "libraryx",
    is_doc_only = false,
}

function LibraryX:init()
    Debug.log("plugin init")
    if not self.ui.document and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
end

function LibraryX:getLibraryRoot()
    return G_reader_settings:readSetting(ROOT_KEY)
end

function LibraryX:setLibraryRoot(path)
    G_reader_settings:saveSetting(ROOT_KEY, path)
    Debug.log("library root set", path)
end

function LibraryX:chooseLibraryRoot()
    local chooser
    chooser = PathChooser:new{
        title = _("Choose LibraryX folder"),
        path = self:getLibraryRoot() or G_reader_settings:readSetting("home_dir") or "/mnt/us",
        select_directory = true,
        select_file = false,
        show_files = false,
        onConfirm = function(path)
            self:setLibraryRoot(path)
            UIManager:show(InfoMessage:new{
                text = _("Library folder selected:") .. "\n" .. path,
                timeout = 3,
            })
        end,
    }
    UIManager:show(chooser)
end

function LibraryX:scanLibrary()
    local root = self:getLibraryRoot()
    if not root then
        UIManager:show(InfoMessage:new{
            text = _("Choose a library folder first."),
            timeout = 3,
        })
        self:chooseLibraryRoot()
        return
    end

    local info = InfoMessage:new{
        text = _("LibraryX is scanning…") .. "\n" .. root,
    }
    UIManager:show(info)
    UIManager:nextTick(function()
        Debug.log("scan start", root)
        local repo = LibraryRepo.new()
        local scanner = Scanner.new(self.ui, repo)
        local ok, stats = pcall(scanner.scanRoot, scanner, root, {
            on_error = function(path, err)
                Debug.log("scan error", path, err)
            end,
            on_progress = function(s, path)
                if s.visited % 25 == 0 then
                    Debug.log("scan progress", s.visited, path)
                end
            end,
        })
        repo.storage:close()
        UIManager:close(info)

        if not ok then
            Debug.log("scan fatal", stats)
            UIManager:show(InfoMessage:new{
                text = _("Library scan failed.") .. "\n" .. tostring(stats),
            })
            return
        end

        Debug.log("scan finish",
            "visited=" .. stats.visited,
            "indexed=" .. stats.indexed,
            "unchanged=" .. stats.unchanged,
            "unsupported=" .. stats.unsupported,
            "errors=" .. stats.errors)

        UIManager:show(InfoMessage:new{
            text = string.format(
                "LibraryX scan complete\n\nFiles: %d\nIndexed: %d\nUnchanged: %d\nUnsupported: %d\nErrors: %d",
                stats.visited, stats.indexed, stats.unchanged,
                stats.unsupported, stats.errors),
        })
    end)
end

function LibraryX:openLibrary()
    local ui = LibraryUI.new(self)
    ui:showRoot()
end

function LibraryX:showDebugMenu()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    dialog = ButtonDialog:new{
        title = _("LibraryX debug"),
        buttons = {
            {
                {
                    text = _("Report"),
                    callback = function()
                        UIManager:close(dialog)
                        DebugUI.report(self)
                    end,
                },
                {
                    text = _("Clear log"),
                    callback = function()
                        Debug.clear()
                        UIManager:close(dialog)
                        UIManager:show(InfoMessage:new{ text = _("Debug log cleared."), timeout = 2 })
                    end,
                },
            },
            {
                {
                    text = _("Compatibility probe"),
                    callback = function()
                        UIManager:close(dialog)
                        require("compat").run(self)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function LibraryX:addToMainMenu(menu_items)
    menu_items.libraryx = {
        text = _("LibraryX [DEBUG]"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Open LibraryX"),
                callback = function() self:openLibrary() end,
            },
            {
                text = _("Scan library"),
                callback = function() self:scanLibrary() end,
            },
            {
                text_func = function()
                    local root = self:getLibraryRoot()
                    return root and (_("Library folder:") .. " " .. root)
                        or _("Choose library folder")
                end,
                callback = function() self:chooseLibraryRoot() end,
            },
            {
                text = _("Debug"),
                callback = function() self:showDebugMenu() end,
            },
        },
    }
end

return LibraryX
