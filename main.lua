local InfoMessage = require("ui/widget/infomessage")
local PathChooser = require("ui/widget/pathchooser")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local LibraryRepo = require("libraryrepo")
local LibraryUI = require("libraryui")
local Scanner = require("scanner")
local Debug = require("libraryxdebug")
local DebugUI = require("debugui")
local L = require("libraryxi18n").t

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

function LibraryX:refreshLibraryMenu()
    if self.library_menu then
        self.library_menu:updateItems()
    end
end

function LibraryX:setLibraryRoot(path)
    G_reader_settings:saveSetting(ROOT_KEY, path)
    Debug.log("library root set", path)
    self:refreshLibraryMenu()
end

function LibraryX:chooseLibraryRoot()
    local chooser = PathChooser:new{
        title = L("choose_libraryx_folder"),
        path = self:getLibraryRoot()
            or G_reader_settings:readSetting("home_dir")
            or "/mnt/us",
        select_directory = true,
        select_file = false,
        show_files = false,
        onConfirm = function(path)
            self:setLibraryRoot(path)
            UIManager:show(InfoMessage:new{
                text = L("folder_selected") .. "\n" .. path,
                timeout = 3,
            })
        end,
    }
    UIManager:show(chooser)
end

function LibraryX:_scanLibraryWrapped(root)
    local Trapper = require("ui/trapper")
    Trapper:setPausedText(L("scan_paused"), L("abort"), L("continue"))

    Debug.log("scan start", root)
    if not Trapper:info(L("scanning") .. "\n\n" .. root) then
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
            local processed = st.indexed + st.unchanged + st.errors
            if processed - last_ui_update >= 10 then
                last_ui_update = processed
                local text = string.format(
                    "%s\n\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n\n%s",
                    L("scan_progress"),
                    L("files_seen"), st.visited,
                    L("indexed"), st.indexed,
                    L("unchanged"), st.unchanged,
                    L("errors"), st.errors,
                    path)
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
            text = L("scan_failed") .. "\n\n" .. tostring(stats),
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
                "%s\n\n%s: %d\n%s: %d\n%s: %d\n%s: %d",
                L("scan_cancelled"),
                L("files_seen"), stats.visited,
                L("indexed"), stats.indexed,
                L("unchanged"), stats.unchanged,
                L("errors"), stats.errors),
        })
        self:refreshLibraryMenu()
        return
    end

    Debug.log("scan finish",
        "visited=" .. stats.visited,
        "indexed=" .. stats.indexed,
        "unchanged=" .. stats.unchanged,
        "unsupported=" .. stats.unsupported,
        "errors=" .. stats.errors)

    self:refreshLibraryMenu()
    UIManager:show(InfoMessage:new{
        text = string.format(
            "%s\n\n%s: %d\n%s: %d\n%s: %d\n%s: %d\n%s: %d",
            L("scan_complete"),
            L("files_seen"), stats.visited,
            L("indexed"), stats.indexed,
            L("unchanged"), stats.unchanged,
            L("unsupported"), stats.unsupported,
            L("errors"), stats.errors),
    })
end

function LibraryX:scanLibrary()
    local root = self:getLibraryRoot()
    if not root then
        UIManager:show(InfoMessage:new{
            text = L("choose_folder_first"),
            timeout = 3,
        })
        self:chooseLibraryRoot()
        return
    end

    local Trapper = require("ui/trapper")
    Trapper:wrap(function()
        local ok, err = xpcall(function()
            self:_scanLibraryWrapped(root)
        end, debug.traceback)
        if not ok then
            Debug.log("scan uncaught error", err)
            Trapper:clear()
            UIManager:show(InfoMessage:new{
                text = L("internal_error") .. "\n\n" .. tostring(err),
            })
        end
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
        title = L("debug_title"),
        buttons = {
            {
                {
                    text = L("report"),
                    callback = function()
                        UIManager:close(dialog)
                        DebugUI.report(self)
                    end,
                },
                {
                    text = L("clear_log"),
                    callback = function()
                        Debug.clear()
                        UIManager:close(dialog)
                        UIManager:show(InfoMessage:new{
                            text = L("log_cleared"),
                            timeout = 2,
                        })
                    end,
                },
            },
            {
                {
                    text = L("compatibility_probe"),
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
        text = L("libraryx_debug"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = L("open_libraryx"),
                callback = function() self:openLibrary() end,
            },
            {
                text = L("scan_library"),
                callback = function() self:scanLibrary() end,
            },
            {
                text_func = function()
                    local root = self:getLibraryRoot()
                    return root and (L("library_folder") .. ": " .. root)
                        or L("choose_library_folder")
                end,
                callback = function() self:chooseLibraryRoot() end,
            },
            {
                text = L("debug"),
                callback = function() self:showDebugMenu() end,
            },
        },
    }
end

return LibraryX
