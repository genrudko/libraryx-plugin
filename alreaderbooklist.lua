local BookList = require("ui/widget/booklist")
local Font = require("ui/font")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputDialog = require("ui/widget/inputdialog")
local InfoMessage = require("ui/widget/infomessage")
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


local function splitBreadcrumb(title)
    title = tostring(title or "")
    local parent, current = title:match("^(.*)%s/%s([^/]+)$")
    if parent and current then
        return current, parent
    end
    return title, nil
end

local function safeAction(label, fn)
    local ok, err = xpcall(fn, debug.traceback)
    if ok then return true end
    Debug.log(label .. " failed", err)
    UIManager:show(InfoMessage:new{
        text = L("internal_error") .. "\n\n" .. tostring(err),
    })
    return false
end

function AlReaderBookList:init()
    Debug.log("booklist init begin", self.title or "", "items=" .. tostring(#(self.item_table or {})))
    self.files_per_page = tonumber(self.libraryx_files_per_page) or cardsPerPage()
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

function AlReaderBookList:showFooterMenu()
    local dialog
    local current = tonumber(G_reader_settings:readSetting(CARDS_PER_PAGE_KEY))
        or tonumber(self.files_per_page)
        or DEFAULT_CARDS_PER_PAGE

    local function choose(count)
        G_reader_settings:saveSetting(CARDS_PER_PAGE_KEY, count)
        self.files_per_page = count
        if dialog then UIManager:close(dialog) end
        Debug.log("footer scale selected", tostring(count), self.title or "")
        -- Rebuild this exact list in-place. This avoids depending on any
        -- external LibraryUI callback just to make the ⋮ menu functional.
        self:updateItems(1)
    end

    dialog = ButtonDialog:new{
        title = L("list_settings"),
        buttons = {
            {
                {
                    text = L("scale_large") .. (current == 3 and " ✓" or ""),
                    callback = function() choose(3) end,
                },
                {
                    text = L("scale_normal") .. (current == 4 and " ✓" or ""),
                    callback = function() choose(4) end,
                },
            },
            {
                {
                    text = L("scale_compact") .. (current == 5 and " ✓" or ""),
                    callback = function() choose(5) end,
                },
                {
                    text = L("scale_dense") .. (current == 6 and " ✓" or ""),
                    callback = function() choose(6) end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function AlReaderBookList:installAlReaderFooter()
    if not self.page_info then return end

    local WidgetContainer = require("ui/widget/container/widgetcontainer")
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
    local more_w = math.floor(screen_w * 0.11)
    local alpha_w = self.onAlphabetTap and math.floor(screen_w * 0.09) or 0
    local nav_w = math.floor(screen_w * 0.08)
    local close_w = math.floor(screen_w * 0.07)
    local center_w = screen_w - more_w - alpha_w - nav_w - nav_w - close_w

    self.footer_more = Button:new{
        text = "⋮",
        width = more_w,
        bordersize = 0, padding = 0, padding_h = 0, padding_v = 0,
        text_font_size = 18,
        text_font_bold = false,
        callback = function()
            Debug.log("footer more tapped", self.title or "")
            UIManager:nextTick(function()
                safeAction("footer more", function()
                    self:showFooterMenu()
                end)
            end)
        end,
    }
    table.insert(self.page_info, self.footer_more)

    if self.onAlphabetTap then
        self.footer_alpha = Button:new{
            text = L("alphabet_short"),
            width = alpha_w,
            bordersize = 0, padding = 0, padding_h = 0, padding_v = 0,
            text_font_size = 10,
            text_font_bold = false,
            callback = function()
                Debug.log("footer alphabet tapped", self.title or "")
                safeAction("footer alphabet", function()
                    self.onAlphabetTap(self)
                end)
            end,
        }
        table.insert(self.page_info, self.footer_alpha)
    end

    self.footer_prev = Button:new{
        text = "‹",
        width = nav_w,
        bordersize = 0, padding = 0, padding_h = 0, padding_v = 0,
        text_font_size = 24,
        text_font_bold = false,
        callback = function()
            if self.page > 1 then self:onGotoPage(self.page - 1) end
        end,
    }

    self.footer_status = Button:new{
        text = "",
        width = center_w,
        bordersize = 0, padding = 0, padding_h = 0, padding_v = 0,
        text_font_size = 10,
        text_font_bold = false,
        callback = function()
            if self.onSortTap then
                safeAction("footer sort", function() self.onSortTap(self) end)
            end
        end,
    }

    self.footer_next = Button:new{
        text = "›",
        width = nav_w,
        bordersize = 0, padding = 0, padding_h = 0, padding_v = 0,
        text_font_size = 24,
        text_font_bold = false,
        callback = function()
            if self.page < self.page_num then self:onGotoPage(self.page + 1) end
        end,
    }

    self.footer_close = Button:new{
        text = "×",
        width = close_w,
        bordersize = 0, padding = 0, padding_h = 0, padding_v = 0,
        text_font_size = 18,
        text_font_bold = false,
        callback = function() closeWidget(self) end,
    }

    table.insert(self.page_info, self.footer_prev)
    table.insert(self.page_info, self.footer_status)
    table.insert(self.page_info, self.footer_next)
    table.insert(self.page_info, self.footer_close)
    self:updateAlReaderFooter()
end

function AlReaderBookList:updateAlReaderFooter()
    if not self.footer_status then return end

    local label = self.sort_label or L("sort_title_short")
    local page_text = string.format(L("page_of"), self.page, math.max(1, self.page_num))
    self.footer_status:setText(
        string.format("%s\n%s", label, page_text),
        self.footer_status.width)

    if self.page > 1 then self.footer_prev:enable() else self.footer_prev:disable() end
    if self.page < self.page_num then self.footer_next:enable() else self.footer_next:disable() end
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
