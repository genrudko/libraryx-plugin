local Button = require("ui/widget/button")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local L = require("libraryxi18n").t

local AlReaderCatalogMenu = Menu:extend{
    is_borderless = true,
    covers_fullscreen = true,
}

function AlReaderCatalogMenu:init()
    self.full_item_table = self.item_table or {}
    self.custom_title_bar = TitleBar:new{
        width = Screen:getWidth(),
        fullscreen = true,
        align = "left",
        with_bottom_line = true,
        title = self.title or "",
        left_icon = "chevron.left",
        left_icon_size_ratio = 0.75,
        left_icon_tap_callback = function()
            UIManager:close(self)
        end,
        right_icon = self.enable_search ~= false and "appbar.search" or nil,
        right_icon_size_ratio = 0.78,
        right_icon_tap_callback = function()
            if self.enable_search ~= false then self:showSearchDialog() end
        end,
        show_parent = self,
    }

    Menu.init(self)
    self:installFooter()
end

function AlReaderCatalogMenu:installFooter()
    if not self.page_info then return end
    WidgetContainer.clear(self.page_info, true)

    local screen_w = Screen:getWidth()
    local nav_w = math.floor(screen_w * 0.12)
    local close_w = math.floor(screen_w * 0.09)
    local center_w = screen_w - nav_w - nav_w - close_w

    self.footer_prev = Button:new{
        text = "‹", width = nav_w, bordersize = 0, padding = 0,
        text_font_size = 24, text_font_bold = false,
        callback = function()
            if self.page > 1 then self:onGotoPage(self.page - 1) end
        end,
    }
    self.footer_page = Button:new{
        text = "", width = center_w, bordersize = 0, padding = 0,
        text_font_size = 12, text_font_bold = false,
        enabled = false,
    }
    self.footer_next = Button:new{
        text = "›", width = nav_w, bordersize = 0, padding = 0,
        text_font_size = 24, text_font_bold = false,
        callback = function()
            if self.page < self.page_num then self:onGotoPage(self.page + 1) end
        end,
    }
    self.footer_close = Button:new{
        text = "×", width = close_w, bordersize = 0, padding = 0,
        text_font_size = 18, text_font_bold = false,
        callback = function() UIManager:close(self) end,
    }

    table.insert(self.page_info, self.footer_prev)
    table.insert(self.page_info, self.footer_page)
    table.insert(self.page_info, self.footer_next)
    table.insert(self.page_info, self.footer_close)
    self:updateFooter()
end

function AlReaderCatalogMenu:updateFooter()
    if not self.footer_page then return end
    self.footer_page:setText(
        string.format("%s %d / %d", L("page"), self.page, self.page_num),
        self.footer_page.width)
    if self.page > 1 then self.footer_prev:enable() else self.footer_prev:disable() end
    if self.page < self.page_num then self.footer_next:enable() else self.footer_next:disable() end
end

function AlReaderCatalogMenu:updatePageInfo(select_number)
    self:updateFooter()
end

function AlReaderCatalogMenu:showSearchDialog()
    local dialog
    dialog = InputDialog:new{
        title = L("search"),
        input = "",
        buttons = {
            {
                {
                    text = L("cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = L("search"),
                    is_enter_default = true,
                    callback = function()
                        local query = dialog:getInputText() or ""
                        UIManager:close(dialog)
                        local needle = util.stringLower(query)
                        local filtered = {}
                        for _, item in ipairs(self.full_item_table) do
                            local hay = util.stringLower(item.text or "")
                            if query == "" or (hay and hay:find(needle, 1, true)) then
                                filtered[#filtered + 1] = item
                            end
                        end
                        self:switchItemTable(nil, filtered, 1)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return AlReaderCatalogMenu
