local Font = require("ui/font")
local Debug = require("libraryxdebug")
local SafeCardBridge = {}


function SafeCardBridge.densityScale(count)
    count = tonumber(count) or 4
    if count <= 5 then return 1.00 end
    if count == 6 then return 0.86 end
    if count == 7 then return 0.79 end
    if count == 8 then return 0.73 end
    if count == 9 then return 0.68 end
    return 0.63
end


local function placeholderInfo(filepath, display_meta)
    local meta = display_meta and display_meta[filepath] or nil
    return {
        title = meta and meta.title or filepath,
        authors = meta and meta.authors or nil,
        language = meta and meta.language or nil,
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


local function overlayDisplayMetadata(info, meta)
    if not info then return nil end
    if not meta then return info end

    local copy = {}
    for key, value in pairs(info) do
        copy[key] = value
    end
    copy.title = meta.title
    copy.authors = meta.authors
    copy.language = meta.language
    copy.series = meta.series
    copy.series_index = meta.series_index
    copy.has_meta = true
    copy.ignore_meta = false
    return copy
end


local function safeManager(real, display_meta)
    local adapter = {}

    function adapter:getSetting(key)
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

    -- LibraryX owns its list density and presentation settings. Do not leak
    -- ListMenu's internal settings back into CoverBrowser's global config.
    function adapter:saveSetting() end

    function adapter:getBookInfo(filepath, get_cover)
        local ok, info = xpcall(function()
            return real:getBookInfo(filepath, get_cover)
        end, debug.traceback)
        if not ok then
            Debug.log("cover cache read failed", filepath, info)
            -- A broken cache row must never take LibraryX down with it.
            return placeholderInfo(filepath, display_meta)
        end
        return overlayDisplayMetadata(info, display_meta and display_meta[filepath])
    end

    -- IMPORTANT: upstream ListMenu calls these two with DOT syntax, not colon
    -- syntax. Keep them explicit instead of using a generic __index proxy:
    -- the old CoverBridge rebound every function as a method and shifted the
    -- arguments of these static helpers.
    function adapter.isCachedCoverInvalid(bookinfo, cover_specs)
        local ok, invalid = pcall(real.isCachedCoverInvalid, bookinfo, cover_specs)
        if not ok then
            Debug.log("cached cover validation failed", tostring(invalid))
            return false
        end
        return invalid
    end

    function adapter.getCachedCoverSize(img_w, img_h, max_img_w, max_img_h)
        local ok, w, h, scale = pcall(
            real.getCachedCoverSize, img_w, img_h, max_img_w, max_img_h)
        if ok then return w, h, scale end
        Debug.log("cached cover sizing failed", tostring(w))
        if not img_w or not img_h or img_w <= 0 or img_h <= 0 then
            return max_img_w, max_img_h, 1
        end
        local factor = math.min(max_img_w / img_w, max_img_h / img_h)
        return math.max(1, math.floor(img_w * factor + 0.5)),
            math.max(1, math.floor(img_h * factor + 0.5)),
            factor
    end

    function adapter:extractInBackground(files)
        local ok, launched = pcall(real.extractInBackground, real, files)
        if not ok then
            Debug.log("background cover extraction failed", tostring(launched))
            return false
        end
        return launched
    end

    function adapter:extractBookInfo(filepath, cover_specs)
        return real:extractBookInfo(filepath, cover_specs)
    end

    function adapter:isExtractingInBackground()
        local ok, extracting = pcall(real.isExtractingInBackground, real)
        return ok and extracting or false
    end

    function adapter:terminateBackgroundJobs()
        local ok, err = pcall(real.terminateBackgroundJobs, real)
        if not ok then Debug.log("terminate cover jobs failed", tostring(err)) end
    end

    function adapter:closeDbConnection()
        local ok, err = pcall(real.closeDbConnection, real)
        if not ok then Debug.log("close cover db failed", tostring(err)) end
    end

    function adapter:cleanUp()
        local ok, err = pcall(real.cleanUp, real)
        if not ok then Debug.log("cover cleanup failed", tostring(err)) end
    end

    return adapter
end


local function loadModules(display_meta)
    local old_path = package.path
    package.path = "plugins/coverbrowser.koplugin/?.lua;" .. old_path

    local ok_real, real = pcall(require, "bookinfomanager")
    if not ok_real then
        package.path = old_path
        return nil, "BookInfoManager unavailable: " .. tostring(real)
    end

    local old_loaded = package.loaded["bookinfomanager"]
    local adapter = safeManager(real, display_meta or {})
    package.loaded["bookinfomanager"] = adapter

    local ok_cover, CoverMenu = pcall(dofile, "plugins/coverbrowser.koplugin/covermenu.lua")
    local ok_list, ListMenu = pcall(dofile, "plugins/coverbrowser.koplugin/listmenu.lua")

    package.loaded["bookinfomanager"] = old_loaded or real
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

        local ok, build_err = xpcall(function()
            original_build(self)
        end, debug.traceback)
        Font.getFace = original_get_face
        if not ok then error(build_err) end
    end

    menu.display_mode_type = "list"
    menu.files_per_page = tonumber(menu.libraryx_files_per_page)
        or tonumber(menu.files_per_page)
        or tonumber(G_reader_settings:readSetting("libraryx_cards_per_page"))
        or 4

    -- Real covers are handled by KOReader's own BookInfoManager cache and
    -- forked background extractor. The explicit adapter above keeps LibraryX
    -- metadata overrides while preserving the upstream call signatures.
    menu._do_cover_images = true
    menu._do_filename_only = false
    menu._do_hint_opened = false
    menu._libraryx_safe_cards = true

    return true
end

return SafeCardBridge
