local Device = require("device")

local KOReaderMenu = {}

local function zoneCopy(zone)
    return {
        ratio_x = zone.x,
        ratio_y = zone.y,
        ratio_w = zone.w,
        ratio_h = zone.h,
    }
end

function KOReaderMenu.attach(widget, filemanager_menu)
    if not widget or type(widget.registerTouchZones) ~= "function" then
        return false
    end
    if not Device:isTouchDevice() then
        return false
    end
    if not filemanager_menu
            or type(filemanager_menu.onTapShowMenu) ~= "function"
            or type(filemanager_menu.onSwipeShowMenu) ~= "function" then
        return false
    end

    local DTAP_ZONE_MENU = G_defaults:readSetting("DTAP_ZONE_MENU")
    local DTAP_ZONE_MENU_EXT = G_defaults:readSetting("DTAP_ZONE_MENU_EXT")
    if not DTAP_ZONE_MENU or not DTAP_ZONE_MENU_EXT then
        return false
    end

    widget:registerTouchZones({
        {
            id = "libraryx_koreader_menu_tap",
            ges = "tap",
            screen_zone = zoneCopy(DTAP_ZONE_MENU),
            handler = function(ges)
                return filemanager_menu:onTapShowMenu(ges)
            end,
        },
        {
            id = "libraryx_koreader_menu_ext_tap",
            ges = "tap",
            screen_zone = zoneCopy(DTAP_ZONE_MENU_EXT),
            overrides = { "libraryx_koreader_menu_tap" },
            handler = function(ges)
                return filemanager_menu:onTapShowMenu(ges)
            end,
        },
        {
            id = "libraryx_koreader_menu_swipe",
            ges = "swipe",
            screen_zone = zoneCopy(DTAP_ZONE_MENU),
            handler = function(ges)
                return filemanager_menu:onSwipeShowMenu(ges)
            end,
        },
        {
            id = "libraryx_koreader_menu_ext_swipe",
            ges = "swipe",
            screen_zone = zoneCopy(DTAP_ZONE_MENU_EXT),
            overrides = { "libraryx_koreader_menu_swipe" },
            handler = function(ges)
                return filemanager_menu:onSwipeShowMenu(ges)
            end,
        },
    })

    return true
end

return KOReaderMenu
