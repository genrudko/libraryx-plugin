local Font = require("ui/font")
local Debug = require("libraryxdebug")
local SafeCardBridge = {}


function SafeCardBridge.adaptiveProfile(row_height)
    -- Typography follows the actual row geometry, not a hard-coded density
    -- number.  This keeps one font scale for the whole page while allowing
    -- short lists to expand and use the otherwise empty viewport.
    local screen_h = math.max(1, require("device").screen:getHeight())
    local ratio = math.max(0, (tonumber(row_height) or 0) / screen_h)
    if ratio >= 0.16 then return 1.00 end
    if ratio <= 0.08 then return 0.63 end
    return 0.63 + (ratio - 0.08) * (0.37 / 0.08)
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
    local secondary = {}
    if meta.card_context and meta.card_context ~= "" then
        secondary[#secondary + 1] = meta.card_context
    end
    if meta.genres and meta.genres ~= "" then
        secondary[#secondary + 1] = meta.genres
    end
    copy.authors = meta.authors
    if #secondary > 0 then
        copy.authors = (copy.authors and copy.authors ~= "" and (copy.authors .. "\n") or "")
            .. table.concat(secondary, ", ")
    end
    copy.genres = meta.genres
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

    local original_recalculate = modules.ListMenu._recalculateDimen
    menu._recalculateDimen = function(self)
        local target_rows = tonumber(self.libraryx_target_rows)
            or tonumber(self.libraryx_files_per_page)
            or tonumber(G_reader_settings:readSetting("libraryx_cards_per_page"))
            or 4
        local item_count = #(self.item_table or {})
        self.files_per_page = item_count > 0 and math.min(target_rows, item_count) or target_rows
        return original_recalculate(self)
    end

    local original_build = modules.ListMenu._updateItemsBuildUI
    menu._updateItemsBuildUI = function(self)
        local density = SafeCardBridge.adaptiveProfile(self.item_height)
        if density >= 0.999 then return original_build(self) end

        -- Upstream already derives type from row height, but its generous
        -- maximums make dense PW5 rows look nearly as large as sparse ones.
        -- Apply one geometry-derived multiplier to the complete page.
        local original_get_face = Font.getFace
        Font.getFace = function(font_self, name, size, ...)
            if type(size) == "number" and (name == "cfont" or name == "infont") then
                size = math.max(9, math.floor(size * density + 0.5))
            end
            return original_get_face(font_self, name, size, ...)
        end
        local ok, build_err = xpcall(function() original_build(self) end, debug.traceback)
        Font.getFace = original_get_face
        if not ok then error(build_err) end
    end

    menu.display_mode_type = "list"
    menu.libraryx_target_rows = tonumber(menu.libraryx_files_per_page)
        or tonumber(menu.files_per_page)
        or tonumber(G_reader_settings:readSetting("libraryx_cards_per_page"))
        or 4
    local target_rows = menu.libraryx_target_rows
    local item_count = #(menu.item_table or {})
    menu.files_per_page = item_count > 0 and math.min(target_rows, item_count) or target_rows

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
