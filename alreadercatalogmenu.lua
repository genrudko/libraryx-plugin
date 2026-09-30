local Button = require("ui/widget/button")
local Font = require("ui/font")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
local Menu = require("ui/widget/menu")
local Screen = require("device").screen
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local L = require("libraryxi18n").t


local function splitBreadcrumb(title)
    title = tostring(title or "")
    local parent, current = title:match("^(.*)%s/%s([^/]+)$")
    if parent and current then
        return current, parent
    end
    return title, nil
end


local AlReaderCatalogMenu = Menu:extend{
    is_borderless = true,
    covers_fullscreen = true,
    enable_search = true,
    show_back = true,
    show_more = true,
}

function AlReaderCatalogMenu:init()
    self.full_item_table = self.item_table or {}
    self.current_query = nil

    local title_current, title_parent = splitBreadcrumb(self.title)
    self.custom_title_bar = TitleBar:new{
        width = Screen:getWidth(),
        fullscreen = true,
        align = "left",
        with_bottom_line = true,
        title = title_current,
        title_face = Font:getFace("x_smalltfont"),
        title_shrink_font_to_fit = true,
        subtitle = title_parent,
        subtitle_face = Font:getFace("xx_smallinfofont"),
        subtitle_truncate_left = true,
        left_icon = self.show_back ~= false and "chevron.left" or nil,
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

    -- KOReader Menu also keeps a separate bottom-left return_button overlay.
    -- Our AlReader shell already has a back button in the title bar, so that
    -- stock overlay is redundant and, more importantly, it sits on top of
    -- the left edge of page_info and steals taps from our footer ⋮ button.
    -- Remove it completely before installing the custom footer.
    if self.return_button then
        WidgetContainer.clear(self.return_button, true)
    end

    local screen_w = Screen:getWidth()
    local more_w = self.show_more ~= false and math.floor(screen_w * 0.11) or 0
    local alpha_w = self.onAlphabetTap and math.floor(screen_w * 0.09) or 0
    local nav_w = math.floor(screen_w * 0.08)
    local close_w = math.floor(screen_w * 0.07)
    local center_w = screen_w - more_w - alpha_w - nav_w - nav_w - close_w

    if self.show_more ~= false then
        self.footer_more = Button:new{
            text = "⋮", width = more_w, bordersize = 0, padding = 0,
            text_font_size = 18, text_font_bold = false,
            callback = function()
                UIManager:nextTick(function()
                    if self.onMoreTap then
                        self.onMoreTap(self)
                    else
                        UIManager:show(InfoMessage:new{
                            text = L("menu_unavailable"),
                            timeout = 2,
                        })
                    end
                end)
            end,
        }
        table.insert(self.page_info, self.footer_more)
    end

    if self.onAlphabetTap then
        self.footer_alpha = Button:new{
            text = L("alphabet_short"), width = alpha_w,
            bordersize = 0, padding = 0,
            text_font_size = 10, text_font_bold = false,
            callback = function() self.onAlphabetTap(self) end,
        }
        table.insert(self.page_info, self.footer_alpha)
    end

    self.footer_prev = Button:new{
        text = "‹", width = nav_w, bordersize = 0, padding = 0,
        text_font_size = 24, text_font_bold = false,
        callback = function()
            if self.page > 1 then self:onGotoPage(self.page - 1) end
        end,
    }

    self.footer_status = Button:new{
        text = "", width = center_w, bordersize = 0, padding = 0,
        text_font_size = 10, text_font_bold = false,
        callback = function()
            if self.onStatusTap then self.onStatusTap(self) end
        end,
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
    table.insert(self.page_info, self.footer_status)
    table.insert(self.page_info, self.footer_next)
    table.insert(self.page_info, self.footer_close)
    self:updateFooter()
end

function AlReaderCatalogMenu:updateFooter()
    if not self.footer_status then return end

    local label = self.footer_label or ""
    local page_text = string.format(L("page_of"), self.page, math.max(1, self.page_num))
    local text = label ~= "" and string.format("%s\n%s", label, page_text) or page_text
    self.footer_status:setText(text, self.footer_status.width)

    if self.page > 1 then self.footer_prev:enable() else self.footer_prev:disable() end
    if self.page < self.page_num then self.footer_next:enable() else self.footer_next:disable() end
end

function AlReaderCatalogMenu:updatePageInfo(select_number)
    self:updateFooter()
end

function AlReaderCatalogMenu:applySearch(query)
    query = query or ""
    self.current_query = query ~= "" and query or nil

    if query == "" then
        self:switchItemTable(nil, self.full_item_table, 1)
        return
    end

    local needle = util.stringLower(query)
    local filtered = {}
    for _, item in ipairs(self.full_item_table) do
        local hay = util.stringLower(item.libraryx_search_text or item.text or "")
        if hay and hay:find(needle, 1, true) then
            filtered[#filtered + 1] = item
        end
    end
    self:switchItemTable(nil, filtered, 1)
end

function AlReaderCatalogMenu:showSearchDialog()
    local dialog
    dialog = InputDialog:new{
        title = L("search"),
        input = self.current_query or "",
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
                        self:applySearch(query)
                    end,
                },
            },
            {
                {
                    text = L("clear_search"),
                    callback = function()
                        UIManager:close(dialog)
                        self:applySearch("")
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return AlReaderCatalogMenu
