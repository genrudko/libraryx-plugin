local Menu = require("ui/widget/menu")
local ButtonDialog = require("ui/widget/buttondialog")
local InfoMessage = require("ui/widget/infomessage")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local util = require("util")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local LibraryRepo = require("libraryrepo")
local Debug = require("libraryxdebug")
local L = require("libraryxi18n").t

local LibraryUI = {}
LibraryUI.__index = LibraryUI

local SORT_KEY = "libraryx_sort_mode"
local SORT_TITLE = "title"
local SORT_AUTHOR = "author"
local SORT_SERIES = "series"
local SORT_RECENT = "recent"

function LibraryUI.new(plugin, repo)
    return setmetatable({
        plugin = assert(plugin),
        repo = repo or LibraryRepo.new(),
        menus = {},
    }, LibraryUI)
end

local function percent_text(p)
    if type(p) ~= "number" then return nil end
    return string.format("%.1f%%", p * 100)
end

local function first_value(s)
    if not s or s == "" then return "" end
    return s:match("^[^\n]+") or s
end

local function first_utf8(s)
    if not s or s == "" then return "#" end
    local c = s:match(util.UTF8_CHAR_PATTERN)
    if not c then return "#" end
    local upper = {
        ["а"]="А",["б"]="Б",["в"]="В",["г"]="Г",["д"]="Д",["е"]="Е",["ё"]="Ё",
        ["ж"]="Ж",["з"]="З",["и"]="И",["й"]="Й",["к"]="К",["л"]="Л",["м"]="М",
        ["н"]="Н",["о"]="О",["п"]="П",["р"]="Р",["с"]="С",["т"]="Т",["у"]="У",
        ["ф"]="Ф",["х"]="Х",["ц"]="Ц",["ч"]="Ч",["ш"]="Ш",["щ"]="Щ",["ъ"]="Ъ",
        ["ы"]="Ы",["ь"]="Ь",["э"]="Э",["ю"]="Ю",["я"]="Я",
    }
    return upper[c] or c:upper()
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

function LibraryUI:sortKey(book, mode)
    if mode == SORT_AUTHOR then
        return first_value(book.authors)
    elseif mode == SORT_SERIES then
        return book.series or ""
    elseif mode == SORT_RECENT then
        return tonumber(book.last_read_at) or 0
    end
    return book.title or ""
end

function LibraryUI:sortBooks(books, mode)
    table.sort(books, function(a, b)
        if mode == SORT_RECENT then
            local av = tonumber(a.last_read_at) or 0
            local bv = tonumber(b.last_read_at) or 0
            if av ~= bv then return av > bv end
        else
            local av = self:sortKey(a, mode)
            local bv = self:sortKey(b, mode)
            if av ~= bv then return collate(av, bv) end
        end
        local at = a.title or ""
        local bt = b.title or ""
        if at ~= bt then return collate(at, bt) end
        return (a.path or "") < (b.path or "")
    end)
    return books
end

function LibraryUI:bookText(book)
    local lines = {}
    lines[#lines + 1] = book.title or book.path

    if book.authors and book.authors ~= "" then
        lines[#lines + 1] = book.authors:gsub("\n", ", ")
    else
        lines[#lines + 1] = L("unknown_author")
    end

    local meta = {}
    if book.series and book.series ~= "" then
        local series = book.series
        if book.series_index then
            series = series .. " #" .. tostring(book.series_index)
        end
        meta[#meta + 1] = series
    end
    if book.language and book.language ~= "" then
        meta[#meta + 1] = book.language:upper()
    end
    if book.genres and book.genres ~= "" then
        meta[#meta + 1] = book.genres:gsub("\n", ", ")
    end
    if #meta > 0 then
        lines[#lines + 1] = table.concat(meta, " · ")
    end

    local file_meta = {}
    local _, filetype = filemanagerutil.splitFileNameType(book.path)
    file_meta[#file_meta + 1] = (filetype and filetype ~= "" and filetype:upper())
        or (book.format or "")
    if book.filesize and book.filesize > 0 then
        file_meta[#file_meta + 1] = util.getFriendlySize(book.filesize)
    end
    local pct = percent_text(book.percent_finished)
    if pct then file_meta[#file_meta + 1] = pct end
    lines[#lines + 1] = table.concat(file_meta, " · ")

    return table.concat(lines, "\n")
end

function LibraryUI:openBook(menu, book)
    Debug.log("open book", book.path)
    UIManager:close(menu)
    UIManager:nextTick(function()
        ReaderUI:showReader(book.path)
    end)
end

function LibraryUI:buildAlphabetIndex(books, mode)
    if mode == SORT_RECENT then return nil end
    local index = {}
    local order = {}
    for i, book in ipairs(books) do
        local letter = first_utf8(self:sortKey(book, mode))
        if not index[letter] then
            index[letter] = i
            order[#order + 1] = letter
        end
    end
    return index, order
end

function LibraryUI:showAlphabet(menu, books, mode)
    local index, order = self:buildAlphabetIndex(books, mode)
    if not index then
        UIManager:show(InfoMessage:new{ text = L("no_alphabet"), timeout = 3 })
        return
    end

    local rows, row = {}, {}
    local dialog
    for _, letter in ipairs(order) do
        local pos = index[letter]
        row[#row + 1] = {
            text = letter,
            callback = function()
                UIManager:close(dialog)
                menu:updateItems(pos)
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

function LibraryUI:showSortDialog(menu, title, books, mode, reload)
    local dialog
    local function choose(new_mode)
        self:setSortMode(new_mode)
        UIManager:close(dialog)
        UIManager:close(menu)
        reload(new_mode)
    end
    dialog = ButtonDialog:new{
        title = L("sort"),
        buttons = {
            {
                { text = L("sort_title") .. (mode == SORT_TITLE and " ✓" or ""), callback = function() choose(SORT_TITLE) end },
                { text = L("sort_author") .. (mode == SORT_AUTHOR and " ✓" or ""), callback = function() choose(SORT_AUTHOR) end },
            },
            {
                { text = L("sort_series") .. (mode == SORT_SERIES and " ✓" or ""), callback = function() choose(SORT_SERIES) end },
                { text = L("sort_recent") .. (mode == SORT_RECENT and " ✓" or ""), callback = function() choose(SORT_RECENT) end },
            },
            {
                { text = L("alphabet"), callback = function()
                    UIManager:close(dialog)
                    self:showAlphabet(menu, books, mode)
                end },
            },
        },
    }
    UIManager:show(dialog)
end

function LibraryUI:showBooks(title, books, opts)
    opts = opts or {}
    local mode = opts.sort_mode or self:getSortMode()
    self:sortBooks(books, mode)

    local items = {}
    local menu
    for _, book in ipairs(books) do
        local b = book
        items[#items + 1] = {
            text = self:bookText(b),
            callback = function()
                self:openBook(menu, b)
            end,
        }
    end

    local reload = opts.reload or function(new_mode)
        self:showBooks(title, self.repo:listCatalogBooks(10000, 0), {
            sort_mode = new_mode,
        })
    end

    menu = Menu:new{
        title = title,
        subtitle = L("sort_current") .. ": " .. (
            mode == SORT_AUTHOR and L("sort_author")
            or mode == SORT_SERIES and L("sort_series")
            or mode == SORT_RECENT and L("sort_recent")
            or L("sort_title")
        ),
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
        single_line = false,
        multilines_forced = true,
        items_max_lines = 4,
        title_bar_left_icon = "appbar.menu",
        onLeftButtonTap = function()
            self:showSortDialog(menu, title, books, mode, reload)
        end,
    }
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
end

function LibraryUI:showAllBooks(sort_mode)
    local books = self.repo:listCatalogBooks(10000, 0)
    self:showBooks(L("all_books"), books, {
        sort_mode = sort_mode or self:getSortMode(),
        reload = function(new_mode)
            self:showAllBooks(new_mode)
        end,
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
                self:showBooks(L("authors") .. " / " .. a.name,
                    self.repo:listBooksByAuthor(a.id))
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
                self:showBooks(L("series") .. " / " .. sr.name,
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
                self:showBooks(L("folders") .. " / " .. f.name,
                    self.repo:listBooksByFolder(f.name))
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
                self:showBooks(L("recent"), self.repo:listRecent(100), {
                    sort_mode = SORT_RECENT,
                })
            end,
        },
        {
            text = L("scan_library"),
            callback = function() self.plugin:scanLibrary() end,
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
