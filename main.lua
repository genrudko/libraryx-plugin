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
local Settings = require("libraryxsettings")
local Updater = require("libraryxupdater")
local Icons = require("libraryxmenuicons")
local Lifecycle = require("libraryxlifecycle")

local ROOT_KEY = "libraryx_library_root"
local START_WITH_VALUE = "libraryx"
local initial_takeover_done = false
local expect_initial_takeover = false

local LibraryX = WidgetContainer:extend{
    name = "libraryx",
    is_doc_only = false,
}

LibraryX.MENU_ORDER = {
    "libraryx_open",
    "libraryx_favorites",
    "libraryx_folder",
    "libraryx_scan",
    "libraryx_settings",
    "libraryx_updates",
    "libraryx_about",
    "libraryx_debug",
}

function LibraryX:_extendMenuOrder()
    local ok, order = pcall(require, "ui/elements/filemanager_menu_order")
    if not ok or type(order) ~= "table"
            or type(order["KOMenu:menu_buttons"]) ~= "table" then
        return
    end
    local buttons = order["KOMenu:menu_buttons"]
    for _, id in ipairs(buttons) do
        if id == "libraryx_tab" then
            order.libraryx_tab = LibraryX.MENU_ORDER
            return
        end
    end

    local insert_at = 2
    for i, id in ipairs(buttons) do
        if id == "bookshelf_tab" then
            insert_at = i + 1
            break
        end
    end
    table.insert(buttons, insert_at, "libraryx_tab")
    order.libraryx_tab = LibraryX.MENU_ORDER
end

function LibraryX:_extendReaderMenuOrder()
    local ok, order = pcall(require, "ui/elements/reader_menu_order")
    if not ok or type(order) ~= "table"
            or type(order["KOMenu:menu_buttons"]) ~= "table" then
        return
    end

    local buttons = order["KOMenu:menu_buttons"]
    for _, id in ipairs(buttons) do
        if id == "libraryx_reader" then
            order.libraryx_reader = order.libraryx_reader or {}
            return
        end
    end

    local insert_at = #buttons + 1
    for i, id in ipairs(buttons) do
        if id == "filemanager" then
            insert_at = i + 1
            break
        end
    end
    table.insert(buttons, insert_at, "libraryx_reader")
    -- Top-level ReaderMenu buttons are represented as submenus, even when the
    -- tab itself is callback-driven (see reader_menu_order.filemanager = {}).
    -- Without this empty order table MenuSorter treats libraryx_reader as a
    -- regular action, then drops it during top-level cleanup.
    order.libraryx_reader = {}
end

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
    SettingsUI.bind(self)

    if not (self.ui and self.ui.menu) then return end

    if self.ui.document then
        self:_extendReaderMenuOrder()
        self.ui.menu:registerToMainMenu(self)
        -- ReaderMenu builds and caches tab_item_table before external plugins
        -- are instantiated. Invalidate that cache so the next menu open runs
        -- setUpdateItemTable() again with LibraryX in registered_widgets and
        -- with the updated reader_menu_order.
        self.ui.menu.tab_item_table = nil
        return
    end

    self:_extendMenuOrder()
    self:registerStartWith()
    self.ui.menu:registerToMainMenu(self)
    UIManager:scheduleIn(2, function()
        if self.ui and not self.ui.document then
            Updater.checkBackground()
        end
    end)
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

function LibraryX:onShow()
    if self.ui and self.ui.document then return end
    if expect_initial_takeover then
        expect_initial_takeover = false
        self:openLibrary()
    end
end

function LibraryX:onResume()
    if self.ui and not self.ui.document then
        Updater.checkBackground()
    end
end

function LibraryX:onNetworkConnected()
    if self.ui and not self.ui.document then
        Updater.checkBackground()
    end
end

-- KOReader's Exit/Restart event reaches plugins before the host UI starts its
-- CloseWidget cascade. Latch that intent so a Reader close caused by a real
-- application exit is distinguishable from the ordinary "close book -> return
-- to LibraryX" path.
function LibraryX:onExit()
    Lifecycle.noteExit()
end
LibraryX.onRestart = LibraryX.onExit

function LibraryX:onCloseDocument()
    -- CloseDocument is the last point where ReaderUI still owns the document.
    -- On a Reader -> Reader switch, keep the original LibraryX provenance for
    -- the replacement reader. On Exit/Restart, never arm a return.
    if Lifecycle.isExiting() then
        Lifecycle.clearReaderReturn()
        return
    end
    if self.ui and self.ui.tearing_down then
        return
    end
    Lifecycle.prepareReaderReturn()
end

function LibraryX:onCloseWidget()
    -- FileManager sets tearing_down when it is being replaced by ReaderUI.
    -- LibraryX deliberately stays parked underneath so closing the book can
    -- return to the same library view.
    if self.ui and self.ui.tearing_down and not Lifecycle.isExiting() then
        return
    end

    -- ReaderUI has already set self.document=nil by the time CloseWidget is
    -- dispatched, so the return decision must be armed earlier by
    -- onCloseDocument().
    if not Lifecycle.isExiting() and Lifecycle.consumeClosePreservation() then
        return
    end

    Lifecycle.closeAll()
    self.library_menu = nil
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
    SettingsUI.bind(self)
    local ui = LibraryUI.new(self)
    ui:showRoot()
    if Settings.scanOnOpen() then
        UIManager:scheduleIn(0.2, function()
            if self.ui and not self.ui.document then
                self:scanLibrary(false)
            end
        end)
    end
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
    SettingsUI.bind(self)

    if self.ui and self.ui.document then
        menu_items.libraryx_reader = {
            icon = "book.opened",
            text = L("open_libraryx"),
            remember = false,
            callback = function()
                if self.ui and self.ui.menu and self.ui.menu.onTapCloseMenu then
                    self.ui.menu:onTapCloseMenu()
                end
                UIManager:nextTick(function()
                    if self.ui and self.ui.document then
                        self:openLibrary()
                    end
                end)
            end,
        }
        return
    end

    menu_items.libraryx_tab = {
        icon = "book.opened",
        text = L("libraryx"),
    }
    menu_items.libraryx_open = {
        text = Icons.label(Icons.BOOK, L("open_libraryx")),
        callback = function() self:openLibrary() end,
    }
    menu_items.libraryx_favorites = {
        text = Icons.label(Icons.STAR, L("favorites")),
        callback = function()
            local ui = LibraryUI.new(self)
            ui:showFavorites("to_read")
        end,
    }
    menu_items.libraryx_folder = {
        text_func = function()
            local root = self:getLibraryRoot()
            return Icons.label(Icons.FOLDER,
                root and (L("library_folder") .. ": " .. root)
                or L("choose_library_folder"))
        end,
        callback = function() self:chooseLibraryRoot() end,
    }
    menu_items.libraryx_scan = {
        text = Icons.label(Icons.REFRESH, L("update_library")),
        callback = function() self:scanLibrary(false) end,
        separator = true,
    }
    menu_items.libraryx_settings = {
        text = Icons.label(Icons.SETTINGS, L("settings")),
        sub_item_table_func = function()
            return SettingsUI.menu().sub_item_table
        end,
        separator = true,
    }
    menu_items.libraryx_updates = {
        sorting_hint = "libraryx_tab",
        text_func = function()
            local available = Updater.getAvailableUpdate()
            local label = available
                and string.format(L("updates_available_short"), available)
                or L("settings_updates")
            return Icons.label(Icons.UPDATES, label)
        end,
        sub_item_table_func = SettingsUI.updatesMenu,
    }
    menu_items.libraryx_about = {
        text = Icons.label(Icons.INFO, L("about")),
        callback = SettingsUI.showAbout,
    }
    menu_items.libraryx_debug = {
        text = L("debug"),
        callback = function() self:showDebugMenu() end,
    }
end

return LibraryX
