local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LibraryRepo = require("libraryrepo")
local LibraryUI = require("libraryui")
local Scanner = require("scanner")
local Debug = require("libraryxdebug")
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

    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        Trapper:setPausedText(_("Library scan paused.\nContinue scanning or abort?"))
        Trapper:setPausedContinueText(_("Continue"))
        Trapper:setPausedAbortText(_("Abort"))

        Debug.log("scan start", root)
        if not Trapper:info(_("LibraryX is scanning…\nTap to pause/cancel.\n\n") .. root) then
            Debug.log("scan cancelled before traversal")
            return
        end

        local repo = LibraryRepo.new()
        local scanner = Scanner.new(self.ui, repo)
        local cancelled = false
        local last_ui_update = 0

        local ok, stats = pcall(scanner.scanRoot, scanner, root, {
            should_cancel = function()
                return cancelled
            end,
            on_error = function(path, err)
                Debug.log("scan error", path, err)
            end,
            on_progress = function(st, path)
                -- Trapper:info() yields to KOReader's UI loop for ~100 ms.
                -- Do it every 10 supported files: responsive enough on Kindle
                -- without making large libraries painfully slow.
                local processed = st.indexed + st.unchanged + st.errors
                if processed - last_ui_update >= 10 then
                    last_ui_update = processed
                    local text = string.format(
                        "LibraryX scan\nTap to pause/cancel.\n\nFiles seen: %d\nIndexed: %d\nUnchanged: %d\nErrors: %d\n\n%s",
                        st.visited, st.indexed, st.unchanged, st.errors, path)
                    if not Trapper:info(text) then
                        cancelled = true
                        Debug.log("scan cancel requested", "visited=" .. st.visited)
                    end
                end
            end,
        })

        repo.storage:close()
        Trapper:clear()

        if not ok then
            Debug.log("scan fatal", stats)
            UIManager:show(InfoMessage:new{
                text = _("Library scan failed.") .. "\n" .. tostring(stats),
            })
            return
        end

        if stats.cancelled or cancelled then
            Debug.log("scan cancelled",
                "visited=" .. stats.visited,
                "indexed=" .. stats.indexed,
                "unchanged=" .. stats.unchanged)
            UIManager:show(InfoMessage:new{
                text = string.format(
                    "LibraryX scan cancelled safely.\n\nFiles seen: %d\nIndexed: %d\nUnchanged: %d\nErrors: %d",
                    stats.visited, stats.indexed, stats.unchanged, stats.errors),
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
