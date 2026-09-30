local BookList = require("ui/widget/booklist")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputDialog = require("ui/widget/inputdialog")
local Screen = require("device").screen
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local util = require("util")
local SafeCardBridge = require("safecardbridge")
local Debug = require("libraryxdebug")
local L = require("libraryxi18n").t

local CARDS_PER_PAGE_KEY = "libraryx_cards_per_page"
local DEFAULT_CARDS_PER_PAGE = 4
local MIN_CARDS_PER_PAGE = 3
local MAX_CARDS_PER_PAGE = 6

local function cardsPerPage()
    local value = tonumber(G_reader_settings:readSetting(CARDS_PER_PAGE_KEY))
        or DEFAULT_CARDS_PER_PAGE
    return math.max(MIN_CARDS_PER_PAGE, math.min(MAX_CARDS_PER_PAGE, value))
end

local AlReaderBookList = BookList:extend{
    name = "libraryx_books",
    covers_fullscreen = true,
    is_borderless = true,
    files_per_page = 4,
}

local function closeWidget(widget)
    UIManager:close(widget)
end

function AlReaderBookList:init()
    Debug.log("booklist init begin", self.title or "", "items=" .. tostring(#(self.item_table or {})))
    self.files_per_page = tonumber(self.libraryx_files_per_page) or cardsPerPage()
    self.full_item_table = self.item_table or {}
    self.current_query = nil

    self.custom_title_bar = TitleBar:new{
        width = Screen:getWidth(),
        fullscreen = true,
        align = "left",
        with_bottom_line = true,
        title = self.title or "",
        left_icon = "chevron.left",
        left_icon_size_ratio = 0.75,
        left_icon_tap_callback = function()
            closeWidget(self)
        end,
        right_icon = "appbar.search",
        right_icon_size_ratio = 0.78,
        right_icon_tap_callback = function()
            self:showSearchDialog()
        end,
        show_parent = self,
    }

    -- First build a normal BookList so all stock KOReader navigation state exists.
    BookList.init(self)
    Debug.log("booklist base init ok", self.title or "")

    -- Then replace only the list renderer with KOReader's optimized CoverBrowser
    -- renderer. It already handles lazy cover extraction and e-ink repainting.
    local ok, err = SafeCardBridge.patch(self, self.libraryx_display_metadata)
    if not ok then
        Debug.log("safe card bridge failed", err)
    else
        Debug.log("safe card bridge ok", self.title or "")
    end

    self:installAlReaderFooter()
    Debug.log("booklist footer ok", self.title or "")

    local render_ok, render_err = xpcall(function()
        self:updateItems(1)
    end, debug.traceback)
    if not render_ok then
        Debug.log("booklist initial render failed", render_err)
        error(render_err)
    end
    Debug.log("booklist initial render ok", self.title or "")
end

function AlReaderBookList:installAlReaderFooter()
    if not self.page_info then return end

    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    WidgetContainer.clear(self.page_info, true)

    -- Keep the sort label dominant, but reserve real page-turn buttons.
    -- Percentages intentionally match the compact AlReader bottom bar.
    local screen_w = Screen:getWidth()
    local more_w = math.floor(screen_w * 0.07)
    local nav_w = math.floor(screen_w * 0.09)
    local close_w = math.floor(screen_w * 0.07)
    local center_w = screen_w - more_w - nav_w - nav_w - close_w

    local common = {
        bordersize = 0,
        padding = 0,
        padding_h = 0,
        padding_v = 0,
    }

    self.footer_more = Button:new{
        text = "⋮",
        width = more_w,
        bordersize = common.bordersize,
        padding = common.padding,
        padding_h = common.padding_h,
        padding_v = common.padding_v,
        text_font_size = 18,
        text_font_bold = false,
        callback = function()
            if self.onMoreTap then self.onMoreTap(self) end
        end,
    }

    self.footer_prev = Button:new{
        text = "‹",
        width = nav_w,
        bordersize = common.bordersize,
        padding = common.padding,
        padding_h = common.padding_h,
        padding_v = common.padding_v,
        text_font_size = 24,
        text_font_bold = false,
        callback = function()
            if self.page > 1 then
                self:onGotoPage(self.page - 1)
            end
        end,
    }

    self.footer_sort = Button:new{
        text = "",
        width = center_w,
        bordersize = common.bordersize,
        padding = common.padding,
        padding_h = common.padding_h,
        padding_v = common.padding_v,
        text_font_size = 13,
        text_font_bold = false,
        callback = function()
            if self.onSortTap then self.onSortTap(self) end
        end,
    }

    self.footer_next = Button:new{
        text = "›",
        width = nav_w,
        bordersize = common.bordersize,
        padding = common.padding,
        padding_h = common.padding_h,
        padding_v = common.padding_v,
        text_font_size = 24,
        text_font_bold = false,
        callback = function()
            if self.page < self.page_num then
                self:onGotoPage(self.page + 1)
            end
        end,
    }

    self.footer_close = Button:new{
        text = "×",
        width = close_w,
        bordersize = common.bordersize,
        padding = common.padding,
        padding_h = common.padding_h,
        padding_v = common.padding_v,
        text_font_size = 18,
        text_font_bold = false,
        callback = function()
            closeWidget(self)
        end,
    }

    table.insert(self.page_info, self.footer_more)
    table.insert(self.page_info, self.footer_prev)
    table.insert(self.page_info, self.footer_sort)
    table.insert(self.page_info, self.footer_next)
    table.insert(self.page_info, self.footer_close)
    self:updateAlReaderFooter()
end

function AlReaderBookList:updateAlReaderFooter()
    if not self.footer_sort then return end

    local total = #self.item_table
    local first = total > 0 and ((self.page - 1) * self.perpage + 1) or 0
    local last = math.min(self.page * self.perpage, total)
    local label = self.sort_label or L("sort_title")
    self.footer_sort:setText(string.format(
        "%s\n%s\n%d-%d",
        L("sort"), label, first, last))

    if self.footer_prev then
        if self.page > 1 then self.footer_prev:enable() else self.footer_prev:disable() end
    end
    if self.footer_next then
        if self.page < self.page_num then self.footer_next:enable() else self.footer_next:disable() end
    end
end

function AlReaderBookList:updatePageInfo(select_number)
    -- We intentionally replace Menu's visible page navigator with the
    -- AlReader-style footer. Page changes are still handled by Menu/CoverMenu
    -- gestures and key events; only presentation differs.
    self:updateAlReaderFooter()
end

function AlReaderBookList:applySearch(query)
    query = query or ""
    self.current_query = query ~= "" and query or nil

    if query == "" then
        self:switchItemTable(nil, self.full_item_table, 1)
        return
    end

    local needle = util.stringLower(query)
    local filtered = {}
    for _, item in ipairs(self.full_item_table) do
        local haystack = util.stringLower(item.libraryx_search_text or item.text or "")
        if haystack and haystack:find(needle, 1, true) then
            filtered[#filtered + 1] = item
        end
    end
    self:switchItemTable(nil, filtered, 1)
end

function AlReaderBookList:showSearchDialog()
    local dialog
    dialog = InputDialog:new{
        title = L("search_books"),
        input = self.current_query or "",
        buttons = {
            {
                {
                    text = L("cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = L("search"),
                    is_enter_default = true,
                    callback = function()
                        local query = dialog:getInputText()
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

function AlReaderBookList:onCloseWidget()
    -- If CoverBridge patched us, this method is replaced on the instance.
    -- This class implementation is just a safe fallback.
    BookList.onCloseWidget(self)
end

return AlReaderBookList
