local CoverBridge = {}

local function buildProxy(real, display_meta)
    local proxy = {}

    setmetatable(proxy, {
        __index = function(_, key)
            local value = real[key]
            if type(value) == "function" then
                return function(_, ...)
                    return value(real, ...)
                end
            end
            return value
        end,
        __newindex = function(_, key, value)
            real[key] = value
        end,
    })

    function proxy:getSetting(key)
        if key == "series_mode" then
            -- LibraryX provides its own context line below the author.
            return nil
        elseif key == "hide_file_info" then
            return false
        elseif key == "hide_page_info" then
            return false
        elseif key == "no_hint_description" then
            return true
        end
        return real:getSetting(key)
    end

    function proxy:getBookInfo(filepath, do_cover_image)
        local info = real:getBookInfo(filepath, do_cover_image)
        if not info then return nil end

        local override = display_meta and display_meta[filepath]
        if not override then return info end

        local copy = {}
        for key, value in pairs(info) do
            copy[key] = value
        end
        for key, value in pairs(override) do
            copy[key] = value
        end
        copy.has_meta = true
        copy.ignore_meta = false
        return copy
    end

    return proxy
end

local function loadCoverModules(display_meta)
    local old_path = package.path
    package.path = "plugins/coverbrowser.koplugin/?.lua;" .. old_path

    local ok_real, real_or_err = pcall(require, "bookinfomanager")
    if not ok_real then
        package.path = old_path
        return nil, "BookInfoManager unavailable: " .. tostring(real_or_err)
    end
    local real = real_or_err

    local proxy = buildProxy(real, display_meta or {})
    local old_loaded = package.loaded["bookinfomanager"]
    package.loaded["bookinfomanager"] = proxy

    local ok_cover, CoverMenu = pcall(dofile, "plugins/coverbrowser.koplugin/covermenu.lua")
    local ok_list, ListMenu = pcall(dofile, "plugins/coverbrowser.koplugin/listmenu.lua")

    package.loaded["bookinfomanager"] = old_loaded or real
    package.path = old_path

    if not ok_cover or not ok_list then
        return nil, string.format(
            "CoverBrowser bridge unavailable: cover=%s list=%s",
            tostring(CoverMenu), tostring(ListMenu))
    end

    return {
        CoverMenu = CoverMenu,
        ListMenu = ListMenu,
    }
end

function CoverBridge.patch(menu, display_meta)
    local modules, err = loadCoverModules(display_meta)
    if not modules then return nil, err end

    menu.updateItems = modules.CoverMenu.updateItems
    menu.onCloseWidget = modules.CoverMenu.onCloseWidget
    menu._recalculateDimen = modules.ListMenu._recalculateDimen
    menu._updateItemsBuildUI = modules.ListMenu._updateItemsBuildUI

    menu.display_mode_type = "list"
    menu.files_per_page = menu.files_per_page or 4
    menu._do_cover_images = true
    menu._do_filename_only = false
    menu._do_hint_opened = false
    menu._coverbrowser_overridden = true

    return true
end

return CoverBridge
