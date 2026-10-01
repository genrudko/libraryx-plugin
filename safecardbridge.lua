local Font = require("ui/font")
local Size = require("ui/size")
local Screen = require("device").screen
local UIManager = require("ui/uimanager")
local util = require("util")
local Debug = require("libraryxdebug")
local SafeCardBridge = {}


function SafeCardBridge.adaptiveProfile(row_height)
    -- Typography follows the actual row geometry, not a hard-coded density
    -- number.  This keeps one font scale for the whole page while allowing
    -- short lists to expand and use the otherwise empty viewport.
    local screen_h = math.max(1, Screen:getHeight())
    local ratio = math.max(0, (tonumber(row_height) or 0) / screen_h)
    if ratio >= 0.16 then return 1.00 end
    if ratio <= 0.08 then return 0.63 end
    return 0.63 + (ratio - 0.08) * (0.37 / 0.08)
end


local function withAdaptiveFonts(menu, callback)
    local density = SafeCardBridge.adaptiveProfile(menu.item_height)
    if density >= 0.999 then
        return callback()
    end

    local original_get_face = Font.getFace
    Font.getFace = function(font_self, name, size, ...)
        if type(size) == "number" and (name == "cfont" or name == "infont") then
            size = math.max(9, math.floor(size * density + 0.5))
        end
        return original_get_face(font_self, name, size, ...)
    end

    local result
    local ok, err = xpcall(function()
        result = callback()
    end, debug.traceback)
    Font.getFace = original_get_face
    if not ok then error(err) end
    return result
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


local function truncateCardAuthor(text, target_rows)
    text = tostring(text or "")
    target_rows = tonumber(target_rows) or 4
    local max_chars
    if target_rows >= 9 then
        max_chars = 40
    elseif target_rows >= 7 then
        max_chars = 46
    elseif target_rows >= 6 then
        max_chars = 54
    end
    if not max_chars then return text end

    local chars = util.splitToChars(text)
    if #chars <= max_chars then return text end
    local out = {}
    for i = 1, max_chars - 1 do out[i] = chars[i] end
    return table.concat(out) .. "…"
end

local function overlayDisplayMetadata(info, meta, menu)
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
    copy.authors = truncateCardAuthor(
        meta.authors,
        menu and (menu.libraryx_visible_rows or menu.libraryx_target_rows) or nil)
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


local function safeManager(real, display_meta, menu)
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
        return overlayDisplayMetadata(info, display_meta and display_meta[filepath], menu)
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


local function loadModules(display_meta, menu)
    local old_path = package.path
    package.path = "plugins/coverbrowser.koplugin/?.lua;" .. old_path

    local ok_real, real = pcall(require, "bookinfomanager")
    if not ok_real then
        package.path = old_path
        return nil, "BookInfoManager unavailable: " .. tostring(real)
    end

    local old_loaded = package.loaded["bookinfomanager"]
    local adapter = safeManager(real, display_meta or {}, menu)
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
    local modules, err = loadModules(display_meta, menu)
    if not modules then return nil, err end

    local original_update = modules.CoverMenu.updateItems
    menu.updateItems = function(self, select_number, no_recalculate_dimen)
        local result = original_update(self, select_number, no_recalculate_dimen)

        -- CoverBrowser refreshes newly indexed rows later via item:update().
        -- Those callbacks bypass _updateItemsBuildUI(), so without wrapping
        -- them they use upstream font sizes until the next page/re-entry.
        local original_action = self.items_update_action
        if original_action and #(self.items_to_update or {}) > 0 then
            UIManager:unschedule(original_action)
            local wrapped_action
            wrapped_action = function()
                return withAdaptiveFonts(self, original_action)
            end
            self.items_update_action = wrapped_action
            UIManager:scheduleIn(1, wrapped_action)
        end

        return result
    end
    menu.onCloseWidget = modules.CoverMenu.onCloseWidget
    menu._recalculateDimen = modules.ListMenu._recalculateDimen

    local original_recalculate = modules.ListMenu._recalculateDimen
    menu._recalculateDimen = function(self)
        local target_rows = tonumber(self.libraryx_target_rows)
            or tonumber(self.libraryx_files_per_page)
            or tonumber(G_reader_settings:readSetting("libraryx_cards_per_page"))
            or 4

        -- Keep pagination stable at the selected target density.  Only the
        -- current page's visual row height adapts when that page is short.
        self.files_per_page = target_rows
        local result = original_recalculate(self)

        local item_count = #(self.item_table or {})
        local page = math.max(1, tonumber(self.page) or 1)
        local first_index = (page - 1) * target_rows + 1
        local remaining = math.max(0, item_count - first_index + 1)
        local visible_rows = math.min(target_rows, remaining)
        self.libraryx_visible_rows =
            visible_rows > 0 and visible_rows or target_rows
        if visible_rows > 0 and visible_rows < target_rows then
            local available_height =
                self.inner_dimen.h - self.others_height - Size.line.thin
            self.item_height =
                math.floor(available_height / visible_rows) - Size.line.thin
            self.item_dimen.h = self.item_height
        end
        return result
    end

    local original_build = modules.ListMenu._updateItemsBuildUI
    menu._updateItemsBuildUI = function(self)
        -- Upstream already derives type from row height, but its generous
        -- maximums make dense PW5 rows look nearly as large as sparse ones.
        -- Apply one geometry-derived multiplier to the complete page.
        return withAdaptiveFonts(self, function()
            return original_build(self)
        end)
    end

    menu.display_mode_type = "list"
    menu.libraryx_target_rows = tonumber(menu.libraryx_files_per_page)
        or tonumber(menu.files_per_page)
        or tonumber(G_reader_settings:readSetting("libraryx_cards_per_page"))
        or 4
    menu.files_per_page = menu.libraryx_target_rows

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
