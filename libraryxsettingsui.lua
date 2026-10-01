local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local SpinWidget = require("ui/widget/spinwidget")
local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local TouchMenu = require("ui/widget/touchmenu")
local Settings = require("libraryxsettings")
local L = require("libraryxi18n").t

local SettingsUI = {}

local function refresh(touchmenu_instance)
    if touchmenu_instance and touchmenu_instance.updateItems then
        touchmenu_instance:updateItems()
    end
end

local function percentItem(label_key, setting_key, minv, maxv, default)
    return {
        text_func = function()
            return string.format("%s: %d%%", L(label_key), Settings.get(setting_key))
        end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            UIManager:show(SpinWidget:new{
                value = Settings.get(setting_key),
                value_min = minv,
                value_max = maxv,
                value_step = 5,
                value_hold_step = 10,
                default_value = default,
                unit = "%",
                title_text = L(label_key),
                callback = function(spin)
                    Settings.set(setting_key, spin.value)
                    refresh(touchmenu_instance)
                end,
            })
        end,
    }
end

local function toggleItem(label_key, setting_key)
    return {
        text_func = function() return L(label_key) end,
        checked_func = function() return Settings.get(setting_key) end,
        keep_menu_open = true,
        callback = function(touchmenu_instance)
            Settings.set(setting_key, not Settings.get(setting_key))
            refresh(touchmenu_instance)
        end,
    }
end

local function densityItems()
    local items = {
        {
            text_func = function() return L("density_auto") end,
            radio = true,
            checked_func = function() return Settings.get("list_density") == "auto" end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                Settings.set("list_density", "auto")
                refresh(touchmenu_instance)
            end,
        },
    }
    for n = 3, 10 do
        local count = n
        items[#items + 1] = {
            text_func = function()
                return string.format(L("books_per_screen"), count)
            end,
            radio = true,
            checked_func = function() return Settings.get("list_density") == count end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                Settings.set("list_density", count)
                refresh(touchmenu_instance)
            end,
        }
    end
    return items
end

local function languageItems()
    local choices = {
        { value = "system", label = "language_system" },
        { value = "ru", label = "language_russian" },
        { value = "en", label = "language_english" },
    }
    local items = {}
    for _, choice in ipairs(choices) do
        local value, label = choice.value, choice.label
        items[#items + 1] = {
            text_func = function() return L(label) end,
            radio = true,
            checked_func = function() return Settings.language() == value end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                Settings.set("language", value)
                refresh(touchmenu_instance)
                UIManager:show(InfoMessage:new{
                    text = L("language_applies_next_open"),
                    timeout = 2,
                })
            end,
        }
    end
    return items
end

function SettingsUI.menu()
    return {
        text_func = function() return L("settings") end,
        sub_item_table = {
            {
                text_func = function() return L("settings_book_list") end,
                sub_item_table = {
                    {
                        text_func = function()
                            local density = Settings.get("list_density")
                            local value = density == "auto"
                                and L("density_auto")
                                or string.format(L("books_per_screen"), density)
                            return L("list_density") .. ": " .. value
                        end,
                        sub_item_table = densityItems(),
                    },
                    percentItem("list_font_scale", "list_font_scale", 80, 120, 100),
                    toggleItem("show_genres", "list_show_genres"),
                    toggleItem("show_language", "list_show_language"),
                    toggleItem("show_series_index", "list_show_series_index"),
                    toggleItem("show_file_info", "list_show_file_info"),
                },
            },
            {
                text_func = function() return L("settings_book_details") end,
                sub_item_table = {
                    percentItem("details_body_scale", "details_body_scale", 70, 130, 90),
                    percentItem("details_title_scale", "details_title_scale", 80, 130, 100),
                    percentItem("details_cover_scale", "details_cover_scale", 60, 110, 100),
                    toggleItem("show_genres", "details_show_genres"),
                    toggleItem("show_metadata", "details_show_metadata"),
                    toggleItem("show_path", "details_show_path"),
                },
            },
            {
                text_func = function()
                    local labels = {
                        system = L("language_system"),
                        ru = L("language_russian"),
                        en = L("language_english"),
                    }
                    return L("settings_language") .. ": " .. labels[Settings.language()]
                end,
                sub_item_table = languageItems(),
            },
            {
                text_func = function() return L("reset_settings") end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = L("reset_settings_confirm"),
                        ok_text = L("reset"),
                        ok_callback = function()
                            Settings.resetAll()
                            refresh(touchmenu_instance)
                            UIManager:show(InfoMessage:new{
                                text = L("settings_reset_done"),
                                timeout = 2,
                            })
                        end,
                    })
                end,
            },
        },
    }
end


function SettingsUI.show()
    local root = SettingsUI.menu()
    local tab = { icon = "appbar.settings" }
    for _, item in ipairs(root.sub_item_table or {}) do
        tab[#tab + 1] = item
    end

    local menu = TouchMenu:new{
        title = L("settings"),
        width = Screen:getWidth(),
        tab_item_table = { tab },
    }
    UIManager:show(menu)
    return menu
end

return SettingsUI
