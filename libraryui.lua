local Menu = require("ui/widget/menu")
local TextViewer = require("ui/widget/textviewer")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local util = require("util")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local LibraryRepo = require("libraryrepo")
local AlReaderBookList = require("alreaderbooklist")
local Debug = require("libraryxdebug")
local L = require("libraryxi18n").t

local LibraryUI = {}
LibraryUI.__index = LibraryUI

local SORT_KEY = "libraryx_sort_mode"
local SORT_REVERSE_KEY = "libraryx_sort_reverse"
local SERIES_SORT_KEY = "libraryx_series_sort_mode"
local SERIES_SORT_REVERSE_KEY = "libraryx_series_sort_reverse"
local SERIES_SORT_STATE_VERSION_KEY = "libraryx_series_sort_state_version"
local SERIES_SORT_STATE_VERSION = 2
local SORT_TITLE = "title"
local SORT_AUTHOR = "author"
local SORT_SERIES = "series"
local SORT_RECENT = "recent"
local SORT_ADDED = "added"
local SORT_FILEDATE = "filedate"
local SORT_SERIES_INDEX = "series_index"

function LibraryUI.new(plugin, repo)
    return setmetatable({
        plugin = assert(plugin),
        repo = repo or LibraryRepo.new(),
        menus = {},
    }, LibraryUI)
end

local function first_value(s)
    if not s or s == "" then return "" end
    return s:match("^[^\n]+") or s
end

local function collate(a, b)
    if a == b then return false end
    return ffiUtil.strcoll(a or "", b or "")
end

function LibraryUI:getSortMode()
    return G_reader_settings:readSetting(SORT_KEY) or SORT_TITLE
end

function LibraryUI:setSortMode(mode)
    G_reader_settings:saveSetting(SORT_KEY, mode)
end

function LibraryUI:getSortReverse()
    return G_reader_settings:isTrue(SORT_REVERSE_KEY)
end

function LibraryUI:setSortReverse(reverse)
    G_reader_settings:saveSetting(SORT_REVERSE_KEY, reverse == true)
end


function LibraryUI:ensureSeriesSortState()
    local version = tonumber(G_reader_settings:readSetting(SERIES_SORT_STATE_VERSION_KEY)) or 0
    if version < SERIES_SORT_STATE_VERSION then
        -- v2 fixes the old persisted reverse flag that made "normal" series
        -- order render as N..1 after the sorting implementation changed.
        G_reader_settings:saveSetting(SERIES_SORT_KEY, SORT_SERIES_INDEX)
        G_reader_settings:saveSetting(SERIES_SORT_REVERSE_KEY, false)
        G_reader_settings:saveSetting(SERIES_SORT_STATE_VERSION_KEY, SERIES_SORT_STATE_VERSION)
    end
end

function LibraryUI:getSeriesSortMode()
    self:ensureSeriesSortState()
    return G_reader_settings:readSetting(SERIES_SORT_KEY) or SORT_SERIES_INDEX
end

function LibraryUI:setSeriesSortMode(mode)
    self:ensureSeriesSortState()
    G_reader_settings:saveSetting(SERIES_SORT_KEY, mode)
end

function LibraryUI:getSeriesSortReverse()
    self:ensureSeriesSortState()
    return G_reader_settings:isTrue(SERIES_SORT_REVERSE_KEY)
end

function LibraryUI:setSeriesSortReverse(reverse)
    G_reader_settings:saveSetting(SERIES_SORT_REVERSE_KEY, reverse == true)
end

function LibraryUI:sortLabel(mode)
    if mode == SORT_AUTHOR then return L("sort_author") end
    if mode == SORT_SERIES then return L("sort_series") end
    if mode == SORT_ADDED then return L("sort_added") end
    if mode == SORT_FILEDATE then return L("sort_filedate") end
    if mode == SORT_RECENT then return L("sort_recent") end
    if mode == SORT_SERIES_INDEX then return L("sort_series_index") end
    return L("sort_title")
end

function LibraryUI:sortKey(book, mode)
    if mode == SORT_AUTHOR then
        return first_value(book.authors)
    elseif mode == SORT_SERIES then
        return book.series or "\u{FFFF}"
    elseif mode == SORT_RECENT then
        return tonumber(book.last_read_at) or 0
    elseif mode == SORT_ADDED then
        return tonumber(book.added_at) or 0
    elseif mode == SORT_FILEDATE then
        return tonumber(book.filemtime) or 0
    elseif mode == SORT_SERIES_INDEX then
        return tonumber(book.series_index)
    end
    return book.title or ""
end

function LibraryUI:sortBooks(books, mode, reverse)
    local function less(a, b)
        if mode == SORT_RECENT or mode == SORT_ADDED or mode == SORT_FILEDATE then
            local field = mode == SORT_RECENT and "last_read_at"
                or mode == SORT_ADDED and "added_at"
                or "filemtime"
            local av = tonumber(a[field]) or 0
            local bv = tonumber(b[field]) or 0
            if av ~= bv then return av > bv end
        elseif mode == SORT_SERIES_INDEX then
            local ai = tonumber(a.series_index)
            local bi = tonumber(b.series_index)
            if ai and bi and ai ~= bi then return ai < bi end
            if ai and not bi then return true end
            if bi and not ai then return false end
        elseif mode == SORT_SERIES then
            local as = a.series or "\u{FFFF}"
            local bs = b.series or "\u{FFFF}"
            if as ~= bs then return collate(as, bs) end
            local ai = tonumber(a.series_index)
            local bi = tonumber(b.series_index)
            if ai and bi and ai ~= bi then return ai < bi end
            if ai and not bi then return true end
            if bi and not ai then return false end
        elseif mode == SORT_AUTHOR then
            local aa = first_value(a.authors)
            local ba = first_value(b.authors)
            if aa ~= ba then return collate(aa, ba) end
        else
            local at = a.title or ""
            local bt = b.title or ""
            if at ~= bt then return collate(at, bt) end
        end

        local at = a.title or ""
        local bt = b.title or ""
        if at ~= bt then return collate(at, bt) end
        return (a.path or "") < (b.path or "")
    end

    table.sort(books, less)

    if reverse then
        local i, j = 1, #books
        while i < j do
            books[i], books[j] = books[j], books[i]
            i, j = i + 1, j - 1
        end
    end
    return books
end

function LibraryUI:bookSearchText(book)
    return table.concat({
        book.title or "",
        book.authors or "",
        book.series or "",
        book.genres or "",
        book.language or "",
    }, "\n")
end

function LibraryUI:toBookListItems(books, opts)
    opts = opts or {}
    local items = {}
    local display_meta = {}

    for _, book in ipairs(books) do
        local b = book
        local authors = (b.authors and b.authors ~= "")
            and b.authors:gsub("\n", ", ")
            or L("unknown_author")

        local context = {}
        if opts.series_context and b.series_index then
            context[#context + 1] = "#" .. tostring(b.series_index)
        end
        if b.language and b.language ~= "" then
            context[#context + 1] = b.language:upper()
        end
        if b.genres and b.genres ~= "" then
            context[#context + 1] = b.genres:gsub("\n", ", ")
        end

        local authors_and_meta = authors
        if #context > 0 then
            authors_and_meta = authors_and_meta .. "\n" .. table.concat(context, ", ")
        end

        display_meta[b.path] = {
            title = b.title,
            authors = authors_and_meta,
            series = nil,
            series_index = nil,
            language = b.language,
        }

        items[#items + 1] = {
            text = b.title or b.path,
            path = b.path,
            file = b.path,
            is_file = true,
            attr = {
                size = b.filesize or 0,
                modification = b.filemtime or 0,
                access = b.last_read_at or 0,
            },
            mandatory = b.filesize and util.getFriendlySize(b.filesize) or "",
            libraryx_book = b,
            libraryx_search_text = self:bookSearchText(b),
            callback = function() end,
        }
    end
    return items, display_meta
end

local function markdownEscape(text)
    text = tostring(text or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub("([%*_#%[%]])", "\\%1")
    return text
end

local function readableDate(ts)
    ts = tonumber(ts)
    if not ts or ts <= 0 then return nil end
    return os.date("%Y-%m-%d %H:%M", ts)
end

function LibraryUI:bookDetailsText(book)
    local lines = {}

    local authors = (book.authors and book.authors ~= "")
        and book.authors:gsub("\n", ", ")
        or L("unknown_author")
    lines[#lines + 1] = "**" .. L("author_label") .. ":** " .. markdownEscape(authors)

    if book.series and book.series ~= "" then
        local series = book.series
        if book.series_index then
            series = series .. " #" .. tostring(book.series_index)
        end
        lines[#lines + 1] = "**" .. L("series_label") .. ":** " .. markdownEscape(series)
    end

    if book.language and book.language ~= "" then
        lines[#lines + 1] = "**" .. L("language_label") .. ":** " .. markdownEscape(book.language:upper())
    end

    if book.genres and book.genres ~= "" then
        lines[#lines + 1] = "**" .. L("genres_label") .. ":** "
            .. markdownEscape(book.genres:gsub("\n", ", "))
    end

    local format = book.format or ""
    local path_l = (book.path or ""):lower()
    if path_l:match("%.fb2%.zip$") then format = "FB2.ZIP" end
    if format ~= "" then
        lines[#lines + 1] = "**" .. L("format_label") .. ":** " .. markdownEscape(format:upper())
    end
    if book.filesize and book.filesize > 0 then
        lines[#lines + 1] = "**" .. L("size_label") .. ":** " .. util.getFriendlySize(book.filesize)
    end

    local progress = tonumber(book.percent_finished)
    if progress then
        lines[#lines + 1] = "**" .. L("progress_label") .. ":** "
            .. string.format("%.2f%%", progress * 100)
    end

    local last_read = readableDate(book.last_read_at)
    lines[#lines + 1] = "**" .. L("last_read_label") .. ":** "
        .. (last_read or L("not_read"))

    local added = readableDate(book.added_at)
    if added then
        lines[#lines + 1] = "**" .. L("added_label") .. ":** " .. added
    end
    local file_date = readableDate(book.filemtime)
    if file_date then
        lines[#lines + 1] = "**" .. L("file_date_label") .. ":** " .. file_date
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "**" .. L("description_label") .. "**"
    local description = book.description
    if description and description ~= "" then
        description = util.htmlToPlainTextIfHtml(description)
        lines[#lines + 1] = markdownEscape(description)
    else
        lines[#lines + 1] = L("no_description")
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "**" .. L("path_label") .. ":** " .. markdownEscape(book.path or "")

    return table.concat(lines, "\n\n")
end

function LibraryUI:showBookDetails(book)
    local full = self.repo:getBookDetails(book.id) or book
    Debug.log("show book details", full.path or "")

    local viewer
    viewer = TextViewer:new{
        title = full.title or util.splitFilePathName(full.path or ""),
        title_multilines = true,
        title_shrink_font_to_fit = true,
        text = self:bookDetailsText(full),
        text_format = "md",
        text_type = "book_info",
        show_menu = false,
        add_default_buttons = false,
        buttons_table = {
            {
                {
                    text = L("read_book"),
                    callback = function()
                        UIManager:close(viewer)
                        UIManager:nextTick(function()
                            ReaderUI:showReader(full.path)
                        end)
                    end,
                },
                {
                    text = L("cover"),
                    callback = function()
                        local bookinfo = self.plugin.ui and self.plugin.ui.bookinfo
                        if bookinfo then
                            bookinfo:onShowBookCover(full.path)
                        end
                    end,
                },
            },
            {
                {
                    text = L("go_to"),
                    callback = function()
                        self:showGoTo(full)
                    end,
                },
                {
                    text = L("close"),
                    callback = function()
                        UIManager:close(viewer)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function LibraryUI:openBook(menu, book)
    Debug.log("open book", book.path)
    UIManager:close(menu)
    UIManager:nextTick(function()
        ReaderUI:showReader(book.path)
    end)
end

function LibraryUI:findAuthorByName(name)
    if not name or name == "" then return nil end
    for _, author in ipairs(self.repo:listAuthors()) do
        if author.name == name then return author end
    end
end

function LibraryUI:showBookInfo(book)
    self:showBookDetails(book)
end

function LibraryUI:showGoTo(book)
    local dialog
    local buttons = {}

    local first_author = first_value(book.authors)
    local author = self:findAuthorByName(first_author)
    if author then
        buttons[#buttons + 1] = {
            {
                text = L("go_to_author"),
                callback = function()
                    UIManager:close(dialog)
                    self:showAuthor(author)
                end,
            },
        }
    end

    if book.series and book.series ~= "" then
        buttons[#buttons + 1] = {
            {
                text = L("go_to_series"),
                callback = function()
                    UIManager:close(dialog)
                    self:showSeriesBooks(
                        L("series") .. " / " .. book.series,
                        self.repo:listBooksBySeries(book.series))
                end,
            },
        }
    end

    local folder = select(1, util.splitFilePathName(book.path))
    if folder and folder ~= "" then
        buttons[#buttons + 1] = {
            {
                text = L("go_to_folder"),
                callback = function()
                    UIManager:close(dialog)
                    local books = self.repo:listBooksByFolder(folder)
                    self:showBooks(L("folders") .. " / " .. folder, books, {
                        sort_mode = SORT_TITLE,
                        reverse = false,
                        reload = function(new_mode, new_reverse)
                            self:showBooks(L("folders") .. " / " .. folder, books, {
                                sort_mode = new_mode,
                                reverse = new_reverse,
                                reload = function() end,
                            })
                        end,
                    })
                end,
            },
        }
    end

    if #buttons == 0 then return end
    dialog = ButtonDialog:new{
        title = L("go_to"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function LibraryUI:showBookActions(menu, book)
    local dialog
    dialog = ButtonDialog:new{
        title = book.title or "",
        buttons = {
            {
                {
                    text = L("read_book"),
                    callback = function()
                        UIManager:close(dialog)
                        self:openBook(menu, book)
                    end,
                },
                {
                    text = L("book_information"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showBookInfo(book)
                    end,
                },
            },
            {
                {
                    text = L("go_to"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showGoTo(book)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

local upper_cyr = {
    ["а"]="А",["б"]="Б",["в"]="В",["г"]="Г",["д"]="Д",["е"]="Е",["ё"]="Ё",
    ["ж"]="Ж",["з"]="З",["и"]="И",["й"]="Й",["к"]="К",["л"]="Л",["м"]="М",
    ["н"]="Н",["о"]="О",["п"]="П",["р"]="Р",["с"]="С",["т"]="Т",["у"]="У",
    ["ф"]="Ф",["х"]="Х",["ц"]="Ц",["ч"]="Ч",["ш"]="Ш",["щ"]="Щ",["ъ"]="Ъ",
    ["ы"]="Ы",["ь"]="Ь",["э"]="Э",["ю"]="Ю",["я"]="Я",
}

local function firstLetter(text)
    if not text or text == "" then return "#" end
    local c = text:match(util.UTF8_CHAR_PATTERN)
    if not c then return "#" end
    return upper_cyr[c] or c:upper()
end

function LibraryUI:alphabetKey(book, mode)
    if mode == SORT_AUTHOR then
        return first_value(book.authors)
    elseif mode == SORT_SERIES then
        return book.series or ""
    elseif mode == SORT_TITLE then
        return book.title or ""
    end
end

function LibraryUI:showAlphabet(menu, books, mode)
    if mode ~= SORT_TITLE and mode ~= SORT_AUTHOR and mode ~= SORT_SERIES then
        local InfoMessage = require("ui/widget/infomessage")
        UIManager:show(InfoMessage:new{
            text = L("no_alphabet"),
            timeout = 3,
        })
        return
    end

    local first_positions = {}
    local letters = {}
    for i, book in ipairs(books) do
        local letter = firstLetter(self:alphabetKey(book, mode))
        if not first_positions[letter] then
            first_positions[letter] = i
            letters[#letters + 1] = letter
        end
    end

    local rows, row = {}, {}
    local dialog
    for _, letter in ipairs(letters) do
        local position = first_positions[letter]
        row[#row + 1] = {
            text = letter,
            callback = function()
                UIManager:close(dialog)
                menu:switchItemTable(nil, nil, position)
            end,
        }
        if #row == 6 then
            rows[#rows + 1] = row
            row = {}
        end
    end
    if #row > 0 then rows[#rows + 1] = row end

    dialog = ButtonDialog:new{
        title = L("alphabet_index"),
        buttons = rows,
    }
    UIManager:show(dialog)
end

function LibraryUI:showListScaleDialog(menu, recreate)
    local current = tonumber(G_reader_settings:readSetting("libraryx_cards_per_page")) or 4
    local dialog

    local function choose(count)
        G_reader_settings:saveSetting("libraryx_cards_per_page", count)
        UIManager:close(dialog)
        if menu then UIManager:close(menu) end
        if recreate then recreate() end
    end

    dialog = ButtonDialog:new{
        title = L("list_scale"),
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

function LibraryUI:showBookListMore(menu, books, mode, recreate)
    local dialog
    dialog = ButtonDialog:new{
        title = L("more"),
        buttons = {
            {
                {
                    text = L("alphabet"),
                    enabled = mode == SORT_TITLE or mode == SORT_AUTHOR or mode == SORT_SERIES,
                    callback = function()
                        UIManager:close(dialog)
                        self:showAlphabet(menu, books, mode)
                    end,
                },
                {
                    text = L("list_scale"),
                    callback = function()
                        UIManager:close(dialog)
                        self:showListScaleDialog(menu, recreate)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function LibraryUI:showSortDialog(menu, opts)
    local mode = opts.sort_mode
    local reverse = opts.reverse == true
    local locked = opts.locked_sort
    local dialog

    local function reload(new_mode, new_reverse)
        UIManager:close(dialog)
        UIManager:close(menu)
        opts.reload(new_mode, new_reverse)
    end

    local rows = {}
    if not locked then
        rows[#rows + 1] = {
            {
                text = L("sort_title") .. (mode == SORT_TITLE and " ✓" or ""),
                callback = function() reload(SORT_TITLE, reverse) end,
            },
            {
                text = L("sort_author") .. (mode == SORT_AUTHOR and " ✓" or ""),
                callback = function() reload(SORT_AUTHOR, reverse) end,
            },
        }
        rows[#rows + 1] = {
            {
                text = L("sort_series") .. (mode == SORT_SERIES and " ✓" or ""),
                callback = function() reload(SORT_SERIES, reverse) end,
            },
            {
                text = L("sort_added") .. (mode == SORT_ADDED and " ✓" or ""),
                callback = function() reload(SORT_ADDED, reverse) end,
            },
        }
        rows[#rows + 1] = {
            {
                text = L("sort_filedate") .. (mode == SORT_FILEDATE and " ✓" or ""),
                callback = function() reload(SORT_FILEDATE, reverse) end,
            },
        }
    end
    rows[#rows + 1] = {
        {
            text = reverse and L("normal_order") or L("reverse_order"),
            callback = function() reload(mode, not reverse) end,
        },
    }

    dialog = ButtonDialog:new{
        title = L("sort"),
        buttons = rows,
    }
    UIManager:show(dialog)
end

function LibraryUI:_showBooks(title, books, opts)
    opts = opts or {}

    local locked = opts.locked_sort
    local mode = locked or opts.sort_mode or self:getSortMode()
    local reverse = opts.reverse
    if reverse == nil then reverse = self:getSortReverse() end

    self:sortBooks(books, mode, reverse)

    local items, display_meta = self:toBookListItems(books, {
        series_context = opts.series_context == true,
    })
    local menu

    local function reload(new_mode, new_reverse)
        if not locked then
            self:setSortMode(new_mode)
            self:setSortReverse(new_reverse)
        end
        opts.reload(new_mode, new_reverse)
    end

    menu = AlReaderBookList:new{
        title = title,
        item_table = items,
        libraryx_display_metadata = display_meta,
        sort_label = self:sortLabel(mode) .. (reverse and " ↓" or ""),
        onMenuSelect = function(_, item)
            self:showBookDetails(item.libraryx_book)
        end,
        onMenuHold = function(_, item)
            self:showBookActions(menu, item.libraryx_book)
        end,
        onSortTap = function()
            self:showSortDialog(menu, {
                sort_mode = mode,
                reverse = reverse,
                locked_sort = locked,
                reload = reload,
            })
        end,
        onMoreTap = function()
            self:showBookListMore(menu, books, mode, function()
                opts.reload(mode, reverse)
            end)
        end,
    }
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
end

function LibraryUI:showBooks(title, books, opts)
    Debug.log("show books begin", title or "", "count=" .. tostring(#(books or {})))
    local ok, err = xpcall(function()
        self:_showBooks(title, books, opts)
    end, debug.traceback)

    if ok then
        Debug.log("show books scheduled", title or "")
        return true
    end

    Debug.log("show books failed", title or "", err)
    UIManager:show(InfoMessage:new{
        text = L("internal_error") .. "\n\n" .. tostring(err),
    })
    return false, err
end


function LibraryUI:showAllBooks(sort_mode, reverse)
    local books = self.repo:listCatalogBooks(10000, 0)
    self:showBooks(L("all_books"), books, {
        sort_mode = sort_mode or self:getSortMode(),
        reverse = reverse,
        reload = function(new_mode, new_reverse)
            self:showAllBooks(new_mode, new_reverse)
        end,
    })
end

function LibraryUI:guardedAction(label, fn)
    Debug.log("guard begin", label or "")
    local ok, result = xpcall(fn, debug.traceback)
    if ok then
        Debug.log("guard ok", label or "")
        return true, result
    end

    Debug.log("guard failed", label or "", result)
    UIManager:show(InfoMessage:new{
        text = L("internal_error") .. "\n\n" .. tostring(result),
    })
    return false, result
end

function LibraryUI:openSeries(series_name, title)
    return self:guardedAction("open series: " .. tostring(series_name), function()
        Debug.log("series query begin", series_name)
        local books = self.repo:listBooksBySeries(series_name)
        Debug.log("series query ok", series_name, "count=" .. tostring(#books))
        self:showSeriesBooks(title, books)
    end)
end

function LibraryUI:showSeriesSortDialog(menu, title, books, mode, reverse)
    local dialog
    local function choose(new_mode, new_reverse)
        self:setSeriesSortMode(new_mode)
        self:setSeriesSortReverse(new_reverse)
        UIManager:close(dialog)
        UIManager:close(menu)
        self:showSeriesBooks(title, books, new_mode, new_reverse)
    end

    dialog = ButtonDialog:new{
        title = L("sort"),
        buttons = {
            {
                {
                    text = L("sort_series_index") .. (mode == SORT_SERIES_INDEX and " ✓" or ""),
                    callback = function() choose(SORT_SERIES_INDEX, reverse) end,
                },
                {
                    text = L("sort_title") .. (mode == SORT_TITLE and " ✓" or ""),
                    callback = function() choose(SORT_TITLE, reverse) end,
                },
            },
            {
                {
                    text = L("sort_author") .. (mode == SORT_AUTHOR and " ✓" or ""),
                    callback = function() choose(SORT_AUTHOR, reverse) end,
                },
                {
                    text = L("sort_added") .. (mode == SORT_ADDED and " ✓" or ""),
                    callback = function() choose(SORT_ADDED, reverse) end,
                },
            },
            {
                {
                    text = L("sort_filedate") .. (mode == SORT_FILEDATE and " ✓" or ""),
                    callback = function() choose(SORT_FILEDATE, reverse) end,
                },
                {
                    text = reverse and L("normal_order") or L("reverse_order"),
                    callback = function() choose(mode, not reverse) end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function LibraryUI:showSeriesBooks(title, books, sort_mode, reverse)
    Debug.log("show series books SAFE CARD", title or "", "count=" .. tostring(#(books or {})))

    local mode = sort_mode or self:getSeriesSortMode()
    if reverse == nil then reverse = self:getSeriesSortReverse() end

    self:sortBooks(books, mode, reverse)

    local items, display_meta = self:toBookListItems(books, {
        series_context = true,
    })

    local menu
    menu = AlReaderBookList:new{
        title = title,
        item_table = items,
        libraryx_display_metadata = display_meta,
        sort_label = self:sortLabel(mode) .. (reverse and " ↓" or ""),
        onMenuSelect = function(_, item)
            self:showBookDetails(item.libraryx_book)
        end,
        onMenuHold = function(_, item)
            self:showBookActions(menu, item.libraryx_book)
        end,
        onSortTap = function()
            self:showSeriesSortDialog(menu, title, books, mode, reverse)
        end,
        onMoreTap = function()
            self:showBookListMore(menu, books, mode, function()
                self:showSeriesBooks(title, books, mode, reverse)
            end)
        end,
    }

    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
    Debug.log("show series books SAFE CARD shown", title or "", "sort=" .. tostring(mode), "reverse=" .. tostring(reverse))
end

function LibraryUI:showAuthor(author)
    local books = self.repo:listBooksByAuthor(author.id)
    local by_series = {}
    local standalone = {}

    for _, book in ipairs(books) do
        if book.series and book.series ~= "" then
            local bucket = by_series[book.series]
            if not bucket then
                bucket = {}
                by_series[book.series] = bucket
            end
            bucket[#bucket + 1] = book
        else
            standalone[#standalone + 1] = book
        end
    end

    local series_names = {}
    for name in pairs(by_series) do
        series_names[#series_names + 1] = name
    end
    table.sort(series_names, collate)

    local items = {}
    for _, name in ipairs(series_names) do
        local series_books = by_series[name]
        items[#items + 1] = {
            text = name,
            mandatory = tostring(#series_books),
            callback = function()
                Debug.log("author series selected", author.name, name, "group_count=" .. tostring(#series_books))
                self:openSeries(
                    name,
                    L("authors") .. " / " .. author.name .. " / " .. name)
            end,
        }
    end

    if #standalone > 0 then
        items[#items + 1] = {
            text = L("standalone_books"),
            mandatory = tostring(#standalone),
            callback = function()
                self:showBooks(
                    L("authors") .. " / " .. author.name .. " / " .. L("standalone_books"),
                    standalone,
                    {
                        sort_mode = SORT_TITLE,
                        reverse = false,
                        reload = function(new_mode, new_reverse)
                            self:showBooks(
                                L("authors") .. " / " .. author.name .. " / " .. L("standalone_books"),
                                standalone,
                                {
                                    sort_mode = new_mode,
                                    reverse = new_reverse,
                                    reload = function() end,
                                })
                        end,
                    })
            end,
        }
    end

    UIManager:show(Menu:new{
        title = L("authors") .. " / " .. author.name,
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:showAuthors()
    local items = {}
    for _, author in ipairs(self.repo:listAuthors()) do
        local a = author
        items[#items + 1] = {
            text = a.name,
            mandatory = tostring(a.count),
            callback = function()
                self:showAuthor(a)
            end,
        }
    end
    UIManager:show(Menu:new{
        title = L("authors"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:showSeries()
    local items = {}
    for _, series in ipairs(self.repo:listSeries()) do
        local sr = series
        items[#items + 1] = {
            text = sr.name,
            mandatory = tostring(sr.count),
            callback = function()
                self:openSeries(
                    sr.name,
                    L("series") .. " / " .. sr.name)
            end,
        }
    end
    UIManager:show(Menu:new{
        title = L("series"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:showFolders()
    local items = {}
    for _, folder in ipairs(self.repo:listFolders()) do
        local f = folder
        items[#items + 1] = {
            text = f.name,
            mandatory = tostring(f.count),
            callback = function()
                local books = self.repo:listBooksByFolder(f.name)
                self:showBooks(L("folders") .. " / " .. f.name, books, {
                    sort_mode = SORT_TITLE,
                    reverse = false,
                    reload = function(new_mode, new_reverse)
                        self:showBooks(L("folders") .. " / " .. f.name, books, {
                            sort_mode = new_mode,
                            reverse = new_reverse,
                            reload = function() end,
                        })
                    end,
                })
            end,
        }
    end
    UIManager:show(Menu:new{
        title = L("folders"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

local function valuesWithCounts(books, getter)
    local counts = {}
    for _, book in ipairs(books) do
        local values = getter(book)
        if type(values) ~= "table" then values = { values } end
        local seen = {}
        for _, value in ipairs(values) do
            if value and value ~= "" and not seen[value] then
                counts[value] = (counts[value] or 0) + 1
                seen[value] = true
            end
        end
    end
    local out = {}
    for value, count in pairs(counts) do
        out[#out + 1] = { value=value, count=count }
    end
    table.sort(out, function(a, b) return collate(a.value, b.value) end)
    return out
end

function LibraryUI:showFilteredBooks(title, source_books, predicate)
    local books = {}
    for _, book in ipairs(source_books) do
        if predicate(book) then books[#books + 1] = book end
    end
    self:showBooks(title, books, {
        sort_mode = SORT_TITLE,
        reverse = false,
        reload = function(new_mode, new_reverse)
            self:showBooks(title, books, {
                sort_mode = new_mode,
                reverse = new_reverse,
                reload = function() end,
            })
        end,
    })
end

function LibraryUI:showValueFilter(title, books, values, predicate, display)
    local items = {}
    for _, entry in ipairs(values) do
        local value = entry.value
        items[#items + 1] = {
            text = display and display(value) or value,
            mandatory = tostring(entry.count),
            callback = function()
                self:showFilteredBooks(
                    title .. " / " .. (display and display(value) or value),
                    books,
                    function(book) return predicate(book, value) end)
            end,
        }
    end
    UIManager:show(Menu:new{
        title = title,
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:showLanguageFilter(books)
    local values = valuesWithCounts(books, function(book)
        return book.language
    end)
    self:showValueFilter(L("filter_language"), books, values,
        function(book, value) return book.language == value end,
        function(value) return value:upper() end)
end

function LibraryUI:showGenreFilter(books)
    local values = valuesWithCounts(books, function(book)
        local out = {}
        for value in (book.genres or ""):gmatch("[^\n]+") do
            out[#out + 1] = value
        end
        return out
    end)
    self:showValueFilter(L("filter_genres"), books, values,
        function(book, value)
            for genre in (book.genres or ""):gmatch("[^\n]+") do
                if genre == value then return true end
            end
            return false
        end)
end

function LibraryUI:showFormatFilter(books)
    local values = valuesWithCounts(books, function(book)
        local path = (book.path or ""):lower()
        if path:match("%.fb2%.zip$") then return "FB2.ZIP" end
        return book.format or ""
    end)
    self:showValueFilter(L("filter_format"), books, values,
        function(book, value)
            local path = (book.path or ""):lower()
            local fmt = path:match("%.fb2%.zip$") and "FB2.ZIP" or (book.format or "")
            return fmt == value
        end)
end

function LibraryUI:showScanDateFilter(books)
    local values = valuesWithCounts(books, function(book)
        local ts = tonumber(book.added_at)
        return ts and os.date("%Y-%m-%d", ts) or nil
    end)
    table.sort(values, function(a, b) return a.value > b.value end)
    self:showValueFilter(L("filter_scan_date"), books, values,
        function(book, value)
            local ts = tonumber(book.added_at)
            return ts and os.date("%Y-%m-%d", ts) == value
        end)
end

function LibraryUI:showFileNoveltyFilter(books)
    local now = os.time()
    local day = 24 * 60 * 60
    local buckets = {
        { text=L("today"), count=0, min=0, max=day },
        { text=L("last_7_days"), count=0, min=day, max=7*day },
        { text=L("last_30_days"), count=0, min=7*day, max=30*day },
        { text=L("older"), count=0, min=30*day, max=math.huge },
    }
    for _, book in ipairs(books) do
        local age = math.max(0, now - (tonumber(book.filemtime) or 0))
        for _, bucket in ipairs(buckets) do
            if age >= bucket.min and age < bucket.max then
                bucket.count = bucket.count + 1
                break
            end
        end
    end

    local items = {}
    for _, bucket in ipairs(buckets) do
        local b = bucket
        items[#items + 1] = {
            text = b.text,
            mandatory = tostring(b.count),
            callback = function()
                self:showFilteredBooks(
                    L("filter_file_novelty") .. " / " .. b.text,
                    books,
                    function(book)
                        local age = math.max(0, now - (tonumber(book.filemtime) or 0))
                        return age >= b.min and age < b.max
                    end)
            end,
        }
    end
    UIManager:show(Menu:new{
        title = L("filter_file_novelty"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:showAdditionalFilter(books)
    local specs = {
        {
            text=L("with_series"),
            predicate=function(book) return book.series and book.series ~= "" end,
        },
        {
            text=L("without_series"),
            predicate=function(book) return not book.series or book.series == "" end,
        },
        {
            text=L("started_books"),
            predicate=function(book)
                return (tonumber(book.percent_finished) or 0) > 0
                    and (tonumber(book.percent_finished) or 0) < 1
            end,
        },
        {
            text=L("unopened_books"),
            predicate=function(book) return not book.last_read_at end,
        },
    }
    local items = {}
    for _, spec in ipairs(specs) do
        local count = 0
        for _, book in ipairs(books) do
            if spec.predicate(book) then count = count + 1 end
        end
        local sp = spec
        items[#items + 1] = {
            text = sp.text,
            mandatory = tostring(count),
            callback = function()
                self:showFilteredBooks(
                    L("filter_additional") .. " / " .. sp.text,
                    books, sp.predicate)
            end,
        }
    end
    UIManager:show(Menu:new{
        title = L("filter_additional"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:showDataFilters()
    local books = self.repo:listCatalogBooks(10000, 0)
    local items = {
        {
            text=L("filter_language"),
            callback=function() self:showLanguageFilter(books) end,
        },
        {
            text=L("filter_genres"),
            callback=function() self:showGenreFilter(books) end,
        },
        {
            text=L("filter_scan_date"),
            callback=function() self:showScanDateFilter(books) end,
        },
        {
            text=L("filter_file_novelty"),
            callback=function() self:showFileNoveltyFilter(books) end,
        },
        {
            text=L("filter_additional"),
            callback=function() self:showAdditionalFilter(books) end,
        },
        {
            text=L("filter_format"),
            callback=function() self:showFormatFilter(books) end,
        },
    }
    UIManager:show(Menu:new{
        title = L("data_filters"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    })
end

function LibraryUI:openRandomBook()
    local books = self.repo:listCatalogBooks(10000, 0)
    if #books == 0 then return end
    -- math.random is fine here: this is a user action, not a reproducible
    -- database operation, and avoids another large correlated SQL projection.
    math.randomseed(os.time() + #books)
    local book = books[math.random(#books)]
    ReaderUI:showReader(book.path)
end

function LibraryUI:showRoot()
    Debug.log("open library root")

    local items = {
        {
            text = L("all_books"),
            mandatory_func = function()
                return tostring(self.repo:countBooks())
            end,
            callback = function()
                self:showAllBooks()
            end,
        },
        {
            text = L("authors"),
            mandatory_func = function()
                return tostring(self.repo:countAuthors())
            end,
            callback = function() self:showAuthors() end,
        },
        {
            text = L("series"),
            mandatory_func = function()
                return tostring(self.repo:countSeries())
            end,
            callback = function() self:showSeries() end,
        },
        {
            text = L("titles"),
            mandatory_func = function()
                return tostring(self.repo:countBooks())
            end,
            callback = function()
                local books = self.repo:listCatalogBooks(10000, 0)
                self:showBooks(L("titles"), books, {
                    locked_sort = SORT_TITLE,
                    reverse = false,
                    reload = function(_, new_reverse)
                        self:showBooks(L("titles"), books, {
                            locked_sort = SORT_TITLE,
                            reverse = new_reverse,
                            reload = function() end,
                        })
                    end,
                })
            end,
        },
        {
            text = L("folders"),
            callback = function() self:showFolders() end,
        },
        {
            text = L("random_book"),
            callback = function() self:openRandomBook() end,
        },
        {
            text = L("data_filters"),
            callback = function() self:showDataFilters() end,
        },
        {
            text = L("scan_library"),
            callback = function() self.plugin:scanLibrary(false) end,
        },
    }

    local menu = Menu:new{
        title = L("libraryx"),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    }
    self.plugin.library_menu = menu
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
end

return LibraryUI
