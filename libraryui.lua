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
    elseif mode == SORT_SERIES_INDEX then
        return tonumber(book.series_index)
    end
    return book.title or ""
end

function LibraryUI:sortBooks(books, mode, reverse)
    local function less(a, b)
        if mode == SORT_RECENT then
            local av = tonumber(a.last_read_at) or 0
            local bv = tonumber(b.last_read_at) or 0
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

function LibraryUI:toBookListItems(books)
    local items = {}
    for _, book in ipairs(books) do
        local b = book
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
    return items
end

function LibraryUI:openBook(menu, book)
    Debug.log("open book", book.path)
    UIManager:close(menu)
    UIManager:nextTick(function()
        ReaderUI:showReader(book.path)
    end)
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
                text = L("sort_recent") .. (mode == SORT_RECENT and " ✓" or ""),
                callback = function() reload(SORT_RECENT, reverse) end,
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

    local items = self:toBookListItems(books)
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
        sort_label = self:sortLabel(mode),
        onMenuSelect = function(_, item)
            self:openBook(menu, item.libraryx_book)
        end,
        onMenuHold = function(_, item)
            -- Context actions are the next UI slice; for now holding opens the book,
            -- which is safer than silently doing nothing on Kindle.
            self:openBook(menu, item.libraryx_book)
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
            self:showSortDialog(menu, {
                sort_mode = mode,
                reverse = reverse,
                locked_sort = locked,
                reload = reload,
            })
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
