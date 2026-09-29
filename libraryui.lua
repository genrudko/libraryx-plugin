local Menu = require("ui/widget/menu")
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
    local bookinfo = self.plugin.ui and self.plugin.ui.bookinfo
    if not bookinfo then return end
    local props = bookinfo:getDocProps(book.path, nil, true)
    if props and bookinfo.extendProps then
        props = bookinfo.extendProps(props, book.path)
    end
    bookinfo:show(book.path, props)
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

function LibraryUI:showBookListMore(menu, books, mode)
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

function LibraryUI:showBooks(title, books, opts)
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
            self:openBook(menu, item.libraryx_book)
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
            self:showBookListMore(menu, books, mode)
        end,
    }
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
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

function LibraryUI:showSeriesBooks(title, books, reverse)
    self:showBooks(title, books, {
        locked_sort = SORT_SERIES_INDEX,
        reverse = reverse == true,
        series_context = true,
        reload = function(_, new_reverse)
            self:showSeriesBooks(title, books, new_reverse)
        end,
    })
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
                self:showSeriesBooks(
                    L("authors") .. " / " .. author.name .. " / " .. name,
                    series_books)
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
                self:showSeriesBooks(
                    L("series") .. " / " .. sr.name,
                    self.repo:listBooksBySeries(sr.name))
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
            text = L("folders"),
            callback = function() self:showFolders() end,
        },
        {
            text = L("recent"),
            callback = function()
                local books = self.repo:listRecent(100)
                self:showBooks(L("recent"), books, {
                    locked_sort = SORT_RECENT,
                    reverse = false,
                    reload = function(_, new_reverse)
                        self:showBooks(L("recent"), books, {
                            locked_sort = SORT_RECENT,
                            reverse = new_reverse,
                            reload = function() end,
                        })
                    end,
                })
            end,
        },
        {
            text = L("update_library"),
            callback = function() self.plugin:scanLibrary(false) end,
        },
        {
            text_func = function()
                local root = self.plugin:getLibraryRoot() or L("not_selected")
                return L("library_folder") .. "\n" .. root
            end,
            callback = function() self.plugin:chooseLibraryRoot() end,
        },
        {
            text = L("debug"),
            callback = function() self.plugin:showDebugMenu() end,
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
