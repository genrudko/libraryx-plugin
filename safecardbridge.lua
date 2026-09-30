local SafeCardBridge = {}

local function fakeManager(display_meta)
    local fake = {}

    function fake:getSetting(key)
        if key == "series_mode" then return nil end
        if key == "hide_file_info" then return false end
        if key == "hide_page_info" then return false end
        if key == "no_hint_description" then return true end
        if key == "fixed_item_font_size" then return true end
        if key == "flash_ui_cover_images" then return false end
        if key == "show_pages_read_as_progress" then return false end
        if key == "show_pages_left_in_progress" then return false end
        return nil
    end

    function fake:saveSetting() end

    function fake:getBookInfo(filepath)
        local meta = display_meta and display_meta[filepath] or nil
        if not meta then
            return {
                title = filepath,
                authors = nil,
                language = nil,
                cover_fetched = true,
                has_cover = false,
                ignore_cover = false,
                ignore_meta = false,
                has_meta = true,
            }
        end
        return {
            title = meta.title,
            authors = meta.authors,
            language = meta.language,
            series = nil,
            series_index = nil,
            description = nil,
            cover_fetched = true,
            has_cover = false,
            ignore_cover = false,
            ignore_meta = false,
            has_meta = true,
        }
    end

    function fake.isCachedCoverInvalid() return false end
    function fake.getCachedCoverSize() return 0, 0, 1 end
    function fake:extractInBackground() return false end
    function fake:isExtractingInBackground() return false end
    function fake:terminateBackgroundJobs() end
    function fake:closeDbConnection() end
    function fake:cleanUp() end

    return fake
end

local function loadModules(display_meta)
    local old_path = package.path
    local old_loaded = package.loaded["bookinfomanager"]
    local fake = fakeManager(display_meta or {})

    package.path = "plugins/coverbrowser.koplugin/?.lua;" .. old_path
    package.loaded["bookinfomanager"] = fake

    local ok_cover, CoverMenu = pcall(dofile, "plugins/coverbrowser.koplugin/covermenu.lua")
    local ok_list, ListMenu = pcall(dofile, "plugins/coverbrowser.koplugin/listmenu.lua")

    package.loaded["bookinfomanager"] = old_loaded
    package.path = old_path

    if not ok_cover or not ok_list then
        return nil, string.format(
            "safe card bridge unavailable: cover=%s list=%s",
            tostring(CoverMenu), tostring(ListMenu))
    end

    return {
        CoverMenu = CoverMenu,
        ListMenu = ListMenu,
    }
end

function SafeCardBridge.patch(menu, display_meta)
    local modules, err = loadModules(display_meta)
    if not modules then return nil, err end

    menu.updateItems = modules.CoverMenu.updateItems
    menu.onCloseWidget = modules.CoverMenu.onCloseWidget
    menu._recalculateDimen = modules.ListMenu._recalculateDimen
    menu._updateItemsBuildUI = modules.ListMenu._updateItemsBuildUI

    menu.display_mode_type = "list"
    menu.files_per_page = tonumber(menu.libraryx_files_per_page)
        or tonumber(menu.files_per_page)
        or tonumber(G_reader_settings:readSetting("libraryx_cards_per_page"))
        or 4

    -- Important: this does NOT request real covers. Fake BookInfoManager always
    -- reports cover_fetched=true + has_cover=false, so ListMenu draws its own
    -- lightweight placeholder and never launches extraction/background jobs.
    menu._do_cover_images = true
    menu._do_filename_only = false
    menu._do_hint_opened = false
    menu._libraryx_safe_cards = true

    return true
end

return SafeCardBridge
