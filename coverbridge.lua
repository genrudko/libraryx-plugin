local CoverBridge = {}

local loaded

local function loadCoverModules()
    if loaded then return loaded end

    local old_path = package.path
    package.path = "plugins/coverbrowser.koplugin/?.lua;" .. old_path

    local ok_cover, CoverMenu = pcall(dofile, "plugins/coverbrowser.koplugin/covermenu.lua")
    local ok_list, ListMenu = pcall(dofile, "plugins/coverbrowser.koplugin/listmenu.lua")

    package.path = old_path

    if not ok_cover or not ok_list then
        return nil, string.format(
            "CoverBrowser bridge unavailable: cover=%s list=%s",
            tostring(CoverMenu), tostring(ListMenu))
    end

    loaded = {
        CoverMenu = CoverMenu,
        ListMenu = ListMenu,
    }
    return loaded
end

function CoverBridge.patch(menu)
    local modules, err = loadCoverModules()
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
