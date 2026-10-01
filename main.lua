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
local SettingsUI = require("libraryxsettingsui")

local ROOT_KEY = "libraryx_library_root"
local START_WITH_VALUE = "libraryx"
local initial_takeover_done = false
local expect_initial_takeover = false

local LibraryX = WidgetContainer:extend{
    name = "libraryx",
    is_doc_only = false,
}

function LibraryX:registerStartWith()
    local ok, FMMenu = pcall(require, "apps/filemanager/filemanagermenu")
    if not ok or not FMMenu or type(FMMenu.getStartWithMenuTable) ~= "function" then
        Debug.log("start_with registration unavailable")
        return
    end
    if FMMenu._libraryx_start_with_patched then return end
    FMMenu._libraryx_start_with_patched = true
    local orig = FMMenu.getStartWithMenuTable
    FMMenu.getStartWithMenuTable = function(fm_menu)
        local result = orig(fm_menu)
        if type(result) ~= "table" or type(result.sub_item_table) ~= "table" then
            return result
        end
        local found = false
        for _, entry in ipairs(result.sub_item_table) do
            if entry.text == L("libraryx") then found = true; break end
        end
        if not found then
            table.insert(result.sub_item_table, {
                text = L("libraryx"),
                radio = true,
                checked_func = function()
                    return G_reader_settings:readSetting("start_with") == START_WITH_VALUE
                end,
                callback = function(touchmenu_instance)
                    G_reader_settings:saveSetting("start_with", START_WITH_VALUE)
                    G_reader_settings:flush()
                    initial_takeover_done = true
                    expect_initial_takeover = false
                    if touchmenu_instance and touchmenu_instance.closeMenu then
                        touchmenu_instance:closeMenu()
                    end
                    if self.ui and not self.ui.document then
                        self:openLibrary()
                    end
                end,
            })
        end
        local orig_text = result.text_func
        result.text_func = function()
            if G_reader_settings:readSetting("start_with") == START_WITH_VALUE then
                return L("start_with_libraryx")
            end
            return orig_text and orig_text() or ""
        end
        return result
    end
end

function LibraryX:init()
    Debug.log("plugin init")
    if not self.ui.document and self.ui.menu then
        self:registerStartWith()
        self.ui.menu:registerToMainMenu(self)
        if G_reader_settings:readSetting("start_with") == START_WITH_VALUE
                and not initial_takeover_done then
            initial_takeover_done = true
            expect_initial_takeover = true
            UIManager:nextTick(function()
                if expect_initial_takeover and self.ui and not self.ui.document then
                    expect_initial_takeover = false
                    self:openLibrary()
                end
            end)
        end
    end
end

function LibraryX:onShow()
    if self.ui and self.ui.document then return end
    if expect_initial_takeover then
        expect_initial_takeover = false
        self:openLibrary()
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

function LibraryX:_scanLibraryWrapped(root, force_reindex)
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
        force_reindex = force_reindex == true,
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

function LibraryX:scanLibrary(force_reindex)
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
            self:_scanLibraryWrapped(root, force_reindex)
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
                {
                    text = L("full_rescan"),
                    callback = function()
                        UIManager:close(dialog)
                        self:scanLibrary(true)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function LibraryX:addToMainMenu(menu_items)
    menu_items.libraryx = {
        text = L("libraryx"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = L("open_libraryx"),
                callback = function() self:openLibrary() end,
            },
            {
                text = L("favorites"),
                callback = function()
                    local ui = LibraryUI.new(self)
                    ui:showFavorites("to_read")
                end,
            },
            {
                text = L("update_library"),
                callback = function() self:scanLibrary(false) end,
            },
            {
                text_func = function()
                    local root = self:getLibraryRoot()
                    return root and (L("library_folder") .. ": " .. root)
                        or L("choose_library_folder")
                end,
                callback = function() self:chooseLibraryRoot() end,
            },
            SettingsUI.menu(),
            {
                text = L("debug"),
                callback = function() self:showDebugMenu() end,
            },
        },
    }
end

return LibraryX
