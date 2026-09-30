local Font = require("ui/font")
local SafeCardBridge = {}


function SafeCardBridge.densityScale(count)
    count = tonumber(count) or 4
    if count <= 5 then return 1.00 end
    if count == 6 then return 0.88 end
    if count == 7 then return 0.86 end
    if count == 8 then return 0.84 end
    if count == 9 then return 0.82 end
    return 0.80
end


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

    local original_build = modules.ListMenu._updateItemsBuildUI
    menu._updateItemsBuildUI = function(self)
        local density = SafeCardBridge.densityScale(self.files_per_page)
        if density >= 0.999 then
            return original_build(self)
        end

        -- KOReader ListMenu already scales fonts from item height, but on PW5
        -- its 24/22/18pt caps keep 6-row mode visually almost as large as 4/5.
        -- Apply an additional deterministic density multiplier while the row
        -- widgets are being built. Restoring Font.getFace immediately keeps
        -- this local to LibraryX and prevents cross-widget side effects.
        local original_get_face = Font.getFace
        Font.getFace = function(font_self, name, size, ...)
            if type(size) == "number"
                and (name == "cfont" or name == "infont")
            then
                size = math.max(9, math.floor(size * density + 0.5))
            end
            return original_get_face(font_self, name, size, ...)
        end

        local ok, err = xpcall(function()
            original_build(self)
        end, debug.traceback)
        Font.getFace = original_get_face
        if not ok then error(err) end
    end

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
