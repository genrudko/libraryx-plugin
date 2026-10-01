local BookDetails = require("libraryxbookdetails")
local CheckButton = require("ui/widget/checkbutton")
local FileManager = require("apps/filemanager/filemanager")
local Screen = require("device").screen
local Font = require("ui/font")
local ButtonDialog = require("ui/widget/buttondialog")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local util = require("util")
local ffiUtil = require("ffi/util")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local LibraryRepo = require("libraryrepo")
local AlReaderBookList = require("alreaderbooklist")
local AlReaderCatalogMenu = require("alreadercatalogmenu")
local Debug = require("libraryxdebug")
local L = require("libraryxi18n").t
local Settings = require("libraryxsettings")

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
local CATALOG_REVERSE_PREFIX = "libraryx_catalog_reverse_"
local TITLES_REVERSE_KEY = "libraryx_titles_reverse"


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

function LibraryUI:sortShortLabel(mode)
    if mode == SORT_AUTHOR then return L("sort_author_short") end
    if mode == SORT_SERIES then return L("sort_series_short") end
    if mode == SORT_ADDED then return L("sort_added_short") end
    if mode == SORT_FILEDATE then return L("sort_filedate_short") end
    if mode == SORT_RECENT then return L("sort_recent_short") end
    if mode == SORT_SERIES_INDEX then return L("sort_series_index_short") end
    return L("sort_title_short")
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

local function sanitizeCardGenres(raw)
    local out={}
    for line in tostring(raw or ""):gmatch("[^\n]+") do
        line=line:gsub("^%s+",""):gsub("%s+$","")
        if line~="" and not line:match("^%d%d%d%d[-.]%d%d[-.]%d%d") and not line:match("^[/\\\\]") and not line:match("^[0-9a-fA-F]{32,}$") then out[#out+1]=line end
    end
    return table.concat(out,", ")
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
        if opts.series_context and b.series_index and Settings.showSeriesIndex() then
            context[#context + 1] = "#" .. tostring(b.series_index)
        end
        if b.language and b.language ~= "" and Settings.showLanguage() then
            context[#context + 1] = b.language:upper()
        end
        local genres = Settings.showGenres() and sanitizeCardGenres(b.genres) or ""
        -- Keep card context deterministic and compact. FB2/EPUB keywords are
        -- often free-form and may contain dates or other cataloging noise, so
        -- only sanitized values are rendered in the visible card.
        display_meta[b.path] = {
            title = b.title,
            authors = authors,
            card_context = table.concat(context, ", "),
            genres = genres,
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
            mandatory = Settings.showFileInfo() and b.filesize
                and util.getFriendlySize(b.filesize) or "",
            libraryx_book = b,
            libraryx_search_text = self:bookSearchText(b),
            callback = function() end,
        }
    end
    return items, display_meta
end

function LibraryUI:showBookDetails(book)
    local full=self.repo:getBookDetails(book.id) or book
    Debug.log("show book details",full.path or "")
    local cover_image
    local bookinfo=self.plugin.ui and self.plugin.ui.bookinfo
    if bookinfo then
        local ok,image=pcall(bookinfo.getCoverImage,bookinfo,nil,full.path)
        if ok then cover_image=image end
    end
    local viewer
    viewer=BookDetails:new{
        plugin=self.plugin,ui=self,book=full,cover_image=cover_image,
        on_read=function()
            UIManager:close(viewer)
            UIManager:nextTick(function() ReaderUI:showReader(full.path) end)
        end,
        on_favorites=function() self:showFavoriteDialog(full) end,
    }
    self.menus[#self.menus+1]=viewer
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
    local rows = {}
    local authors = util.splitToArray(book.authors or "", "\n")
    for _, name in ipairs(authors) do
        local author = self:findAuthorByName(name)
        if author then
            local a = author
            rows[#rows + 1] = {
                name = a.name,
                mandatory = L("go_to_author"),
                callback = function() self:showAuthor(a) end,
            }
        end
    end

    if book.series and book.series ~= "" then
        local series = book.series
        rows[#rows + 1] = {
            name = series,
            mandatory = L("go_to_series"),
            callback = function()
                self:showSeriesBooks(
                    L("series") .. " / " .. series,
                    self.repo:listBooksBySeries(series))
            end,
        }
    end

    rows[#rows + 1] = {
        name = L("library"),
        mandatory = L("go_to_catalog"),
        callback = function() self:showRoot() end,
    }

    self:showCatalogList{
        title = L("go_to"),
        rows = rows,
        kind = "goto:" .. tostring(book.id),
        fixed_order = true,
        alphabet_enabled = false,
        show_more = false,
        recreate = function() self:showGoTo(book) end,
    }
end

function LibraryUI:removeDeletedBookFromMenu(menu,path)
    if not menu or not menu.full_item_table then return end
    for i=#menu.full_item_table,1,-1 do
        local item=menu.full_item_table[i]
        if item.libraryx_book and item.libraryx_book.path == path then
            table.remove(menu.full_item_table,i)
        end
    end
    menu.item_table=menu.full_item_table
    menu:updateItems(1)
end

function LibraryUI:showFavoriteDialog(book)
    local specs=self.repo:listFavoriteCollections()
    local width=math.floor(Screen:getWidth()*0.72)
    local checks={}
    local dialog
    for _,spec in ipairs(specs) do
        local slug=spec.slug
        local check
        check=CheckButton:new{
            text=L(spec.label),
            checked=self.repo:hasFavorite(book.id,slug),
            width=width,
            face=Font:getFace("smallinfofont"),
            callback=function() self.repo:setFavorite(book.id,slug,check.checked) end,
        }
        checks[#checks+1]=check
    end
    dialog=ButtonDialog:new{
        title=L("favorites"),
        width=math.floor(Screen:getWidth()*0.78),
        _added_widgets=checks,
        buttons={{
            {text=L("done"),callback=function() UIManager:close(dialog) end},
        }},
    }
    UIManager:show(dialog)
end

function LibraryUI:showBookActions(menu,book)
    local dialog
    dialog=ButtonDialog:new{
        title=book.title or "",
        buttons={
            {
                {
                    text=L("read_book"),
                    callback=function()
                        UIManager:close(dialog)
                        self:openBook(menu,book)
                    end,
                },
                {
                    text=L("delete_book"),
                    callback=function()
                        UIManager:close(dialog)
                        FileManager:showDeleteFileDialog(book.path,function()
                            self.repo:deleteBookByPath(book.path)
                            self:removeDeletedBookFromMenu(menu,book.path)
                        end)
                    end,
                },
            },
            {
                {
                    text=L("go_to"),
                    callback=function()
                        UIManager:close(dialog)
                        self:showGoTo(book)
                    end,
                },
                {
                    text=L("favorites"),
                    callback=function()
                        UIManager:close(dialog)
                        self:showFavoriteDialog(book)
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
        sort_label = self:sortShortLabel(mode) .. (reverse and " ↓" or ""),
        libraryx_header_left_icon = opts.header_left_icon,
        libraryx_header_left_icon_size_ratio = opts.header_left_icon_size_ratio,
        libraryx_header_left_callback = opts.header_left_callback,
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
        onAlphabetTap = (mode == SORT_TITLE or mode == SORT_AUTHOR or mode == SORT_SERIES)
            and function()
                self:showAlphabet(menu, books, mode)
            end or nil,
        onMoreTap = function()
            self:showBookListMore(menu, books, mode, function()
                opts.reload(mode, reverse)
            end)
        end,
    }
    self.menus[#self.menus + 1] = menu
    if opts.onMenuReady then opts.onMenuReady(menu) end
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
        sort_label = self:sortShortLabel(mode) .. (reverse and " ↓" or ""),
        onMenuSelect = function(_, item)
            self:showBookDetails(item.libraryx_book)
        end,
        onMenuHold = function(_, item)
            self:showBookActions(menu, item.libraryx_book)
        end,
        onSortTap = function()
            self:showSeriesSortDialog(menu, title, books, mode, reverse)
        end,
        onAlphabetTap = (mode == SORT_TITLE or mode == SORT_AUTHOR)
            and function()
                self:showAlphabet(menu, books, mode)
            end or nil,
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

local upper_cyr_catalog = {
    ["а"]="А",["б"]="Б",["в"]="В",["г"]="Г",["д"]="Д",["е"]="Е",["ё"]="Ё",
    ["ж"]="Ж",["з"]="З",["и"]="И",["й"]="Й",["к"]="К",["л"]="Л",["м"]="М",
    ["н"]="Н",["о"]="О",["п"]="П",["р"]="Р",["с"]="С",["т"]="Т",["у"]="У",
    ["ф"]="Ф",["х"]="Х",["ц"]="Ц",["ч"]="Ч",["ш"]="Ш",["щ"]="Щ",["ъ"]="Ъ",
    ["ы"]="Ы",["ь"]="Ь",["э"]="Э",["ю"]="Ю",["я"]="Я",
}

local function catalogFirstLetter(text)
    if not text or text == "" then return "#" end
    local c = text:match(util.UTF8_CHAR_PATTERN)
    if not c then return "#" end
    return upper_cyr_catalog[c] or c:upper()
end

function LibraryUI:getCatalogReverse(kind)
    return G_reader_settings:isTrue(CATALOG_REVERSE_PREFIX .. tostring(kind))
end

function LibraryUI:setCatalogReverse(kind, reverse)
    G_reader_settings:saveSetting(
        CATALOG_REVERSE_PREFIX .. tostring(kind), reverse == true)
end

function LibraryUI:sortCatalogRows(rows, reverse)
    table.sort(rows, function(a, b)
        local an = a.name or a.text or ""
        local bn = b.name or b.text or ""
        if an ~= bn then return collate(an, bn) end
        return (tonumber(a.count) or 0) < (tonumber(b.count) or 0)
    end)
    if reverse then
        local i, j = 1, #rows
        while i < j do
            rows[i], rows[j] = rows[j], rows[i]
            i, j = i + 1, j - 1
        end
    end
    return rows
end

function LibraryUI:showCatalogAlphabet(menu, rows)
    local first_positions = {}
    local letters = {}
    for i, row in ipairs(rows) do
        local letter = catalogFirstLetter(row.name or row.text or "")
        if not first_positions[letter] then
            first_positions[letter] = i
            letters[#letters + 1] = letter
        end
    end

    local dialog
    local buttons, line = {}, {}
    for _, letter in ipairs(letters) do
        local position = first_positions[letter]
        line[#line + 1] = {
            text = letter,
            callback = function()
                UIManager:close(dialog)
                menu:switchItemTable(nil, nil, position)
            end,
        }
        if #line == 6 then
            buttons[#buttons + 1] = line
            line = {}
        end
    end
    if #line > 0 then buttons[#buttons + 1] = line end

    dialog = ButtonDialog:new{
        title = L("alphabet_index"),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

function LibraryUI:showCatalogMore(menu, rows, kind, recreate, alphabet_enabled)
    local reverse = self:getCatalogReverse(kind)
    local dialog = ButtonDialog:new{
        title = L("sort"),
        buttons = {
            {
                {
                    text = reverse and L("normal_order") or L("reverse_order"),
                    callback = function()
                        self:setCatalogReverse(kind, not reverse)
                        UIManager:close(dialog)
                        UIManager:close(menu)
                        recreate()
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

function LibraryUI:showCatalogList(opts)
    local rows = {}
    for _, row in ipairs(opts.rows or {}) do
        rows[#rows + 1] = row
    end

    local reverse = opts.fixed_order and false
        or self:getCatalogReverse(opts.kind or "catalog")
    if not opts.fixed_order then
        self:sortCatalogRows(rows, reverse)
    end

    local items = {}
    local menu
    for _, row in ipairs(rows) do
        local r = row
        items[#items + 1] = {
            text = r.name or r.text or "",
            libraryx_search_text = r.search_text or r.name or r.text or "",
            mandatory = r.count ~= nil and tostring(r.count) or r.mandatory,
            mandatory_func = r.mandatory_func,
            callback = r.callback,
            hold_callback = r.hold_callback,
        }
    end

    local function recreate()
        opts.recreate()
    end

    menu = AlReaderCatalogMenu:new{
        title = opts.title,
        item_table = items,
        enable_search = opts.enable_search ~= false,
        show_back = opts.show_back ~= false,
        show_more = opts.show_more ~= false,
        footer_label = opts.footer_label or
            (opts.fixed_order and "" or L("alphabetical_short")),
        onAlphabetTap = opts.alphabet_enabled ~= false and not opts.fixed_order
            and function()
                self:showCatalogAlphabet(menu, rows)
            end or nil,
        onMoreTap = function()
            if opts.show_more == false then return end
            self:showCatalogMore(
                menu, rows, opts.kind or "catalog", recreate,
                opts.alphabet_enabled ~= false)
        end,
        onStatusTap = function()
            if opts.status_tap then
                opts.status_tap(menu)
            elseif opts.show_more ~= false then
                self:showCatalogMore(
                    menu, rows, opts.kind or "catalog", recreate,
                    opts.alphabet_enabled ~= false)
            end
        end,
    }
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
end

function LibraryUI:showTitles(reverse)
    if reverse == nil then
        reverse = G_reader_settings:isTrue(TITLES_REVERSE_KEY)
    end
    local books = self.repo:listCatalogBooks(10000, 0)
    self:showBooks(L("titles"), books, {
        locked_sort = SORT_TITLE,
        reverse = reverse,
        reload = function(_, new_reverse)
            G_reader_settings:saveSetting(TITLES_REVERSE_KEY, new_reverse == true)
            self:showTitles(new_reverse)
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

    local rows = {}
    for name, series_books in pairs(by_series) do
        local n = name
        local grouped = series_books
        rows[#rows + 1] = {
            name = n,
            count = #grouped,
            callback = function()
                Debug.log("author series selected", author.name, n,
                    "group_count=" .. tostring(#grouped))
                self:openSeries(
                    n,
                    L("authors") .. " / " .. author.name .. " / " .. n)
            end,
        }
    end

    if #standalone > 0 then
        rows[#rows + 1] = {
            name = L("standalone_books"),
            count = #standalone,
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

    self:showCatalogList{
        title = L("authors") .. " / " .. author.name,
        rows = rows,
        kind = "author:" .. tostring(author.id),
        footer_label = L("series_short"),
        recreate = function() self:showAuthor(author) end,
    }
end

function LibraryUI:showAuthors()
    local rows = {}
    for _, author in ipairs(self.repo:listAuthors()) do
        local a = author
        rows[#rows + 1] = {
            name = a.name,
            count = a.count,
            callback = function() self:showAuthor(a) end,
        }
    end

    self:showCatalogList{
        title = L("authors"),
        rows = rows,
        kind = "authors",
        footer_label = L("authors_short"),
        recreate = function() self:showAuthors() end,
    }
end

function LibraryUI:showSeries()
    local rows = {}
    for _, series in ipairs(self.repo:listSeries()) do
        local sr = series
        rows[#rows + 1] = {
            name = sr.name,
            count = sr.count,
            callback = function()
                self:openSeries(
                    sr.name,
                    L("series") .. " / " .. sr.name)
            end,
        }
    end

    self:showCatalogList{
        title = L("series"),
        rows = rows,
        kind = "series",
        footer_label = L("series_short"),
        recreate = function() self:showSeries() end,
    }
end

function LibraryUI:showFolders()
    local rows = {}
    for _, folder in ipairs(self.repo:listFolders()) do
        local f = folder
        rows[#rows + 1] = {
            name = f.name,
            count = f.count,
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

    self:showCatalogList{
        title = L("folders"),
        rows = rows,
        kind = "folders",
        footer_label = L("folders_short"),
        recreate = function() self:showFolders() end,
    }
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
    local rows = {}
    for _, entry in ipairs(values) do
        local value = entry.value
        local label = display and display(value) or value
        rows[#rows + 1] = {
            name = label,
            count = entry.count,
            callback = function()
                self:showFilteredBooks(
                    title .. " / " .. label,
                    books,
                    function(book) return predicate(book, value) end)
            end,
        }
    end

    self:showCatalogList{
        title = title,
        rows = rows,
        kind = "filter:" .. title,
        footer_label = L("filter_short"),
        recreate = function()
            self:showValueFilter(title, books, values, predicate, display)
        end,
    }
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

    local rows = {}
    for _, bucket in ipairs(buckets) do
        local b = bucket
        rows[#rows + 1] = {
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
    self:showCatalogList{
        title = L("filter_file_novelty"),
        rows = rows,
        kind = "filter:file_novelty",
        footer_label = L("filter_short"),
        fixed_order = true,
        alphabet_enabled = false,
        recreate = function() self:showFileNoveltyFilter(books) end,
    }
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
    local rows = {}
    for _, spec in ipairs(specs) do
        local count = 0
        for _, book in ipairs(books) do
            if spec.predicate(book) then count = count + 1 end
        end
        local sp = spec
        rows[#rows + 1] = {
            text = sp.text,
            mandatory = tostring(count),
            callback = function()
                self:showFilteredBooks(
                    L("filter_additional") .. " / " .. sp.text,
                    books, sp.predicate)
            end,
        }
    end
    self:showCatalogList{
        title = L("filter_additional"),
        rows = rows,
        kind = "filter:additional",
        footer_label = L("filter_short"),
        fixed_order = true,
        alphabet_enabled = false,
        recreate = function() self:showAdditionalFilter(books) end,
    }
end

function LibraryUI:showDataFilters()
    local books = self.repo:listCatalogBooks(10000, 0)
    local rows = {
        { name=L("filter_language"), callback=function() self:showLanguageFilter(books) end },
        { name=L("filter_genres"), callback=function() self:showGenreFilter(books) end },
        { name=L("filter_scan_date"), callback=function() self:showScanDateFilter(books) end },
        { name=L("filter_file_novelty"), callback=function() self:showFileNoveltyFilter(books) end },
        { name=L("filter_additional"), callback=function() self:showAdditionalFilter(books) end },
        { name=L("filter_format"), callback=function() self:showFormatFilter(books) end },
    }

    self:showCatalogList{
        title = L("data_filters"),
        rows = rows,
        kind = "filters_root",
        fixed_order = true,
        enable_search = false,
        show_more = false,
        footer_label = L("filters_short"),
        recreate = function() self:showDataFilters() end,
    }
end

function LibraryUI:favoriteLabel(slug)
    if not slug then return L("favorite_all") end
    for _, spec in ipairs(self.repo:listFavoriteCollections()) do
        if spec.slug == slug then return L(spec.label) end
    end
    return L("favorite_all")
end

function LibraryUI:showFavoritePicker(menu, current_slug)
    local dialog
    local rows = {}
    local choices = {{ slug=nil, label="favorite_all" }}
    for _, spec in ipairs(self.repo:listFavoriteCollections()) do
        choices[#choices+1] = { slug=spec.slug, label=spec.label }
    end
    local row = {}
    for _, choice in ipairs(choices) do
        local selected = choice.slug == current_slug
        row[#row+1] = {
            text=L(choice.label) .. (selected and " ✓" or ""),
            callback=function()
                UIManager:close(dialog)
                if menu then UIManager:close(menu) end
                self:showFavorites(choice.slug)
            end,
        }
        if #row == 2 then rows[#rows+1]=row; row={} end
    end
    if #row > 0 then rows[#rows+1]=row end
    dialog=ButtonDialog:new{title=L("favorites"),buttons=rows}
    UIManager:show(dialog)
end

function LibraryUI:showFavorites(slug)
    local selected_slug=slug
    local books=self.repo:listFavoriteBooks(selected_slug)
    local title=L("favorites") .. " / " .. self:favoriteLabel(selected_slug)
    local menu
    local function picker()
        if menu then self:showFavoritePicker(menu,selected_slug) end
    end
    local function options(mode,reverse)
        return {
            sort_mode=mode,reverse=reverse,
            header_left_icon="appbar.menu",
            header_left_icon_size_ratio=0.78,
            header_left_callback=picker,
            onMenuReady=function(m) menu=m end,
        }
    end
    local mode=self:getSortMode()
    local reverse=self:getSortReverse()
    local opts=options(mode,reverse)
    opts.reload=function(new_mode,new_reverse)
        self:setSortMode(new_mode)
        self:setSortReverse(new_reverse)
        local next_opts=options(new_mode,new_reverse)
        next_opts.reload=function() end
        self:showBooks(title,books,next_opts)
    end
    self:showBooks(title,books,opts)
end

function LibraryUI:openRandomBook()
    local books = self.repo:listCatalogBooks(10000, 0)
    if #books == 0 then return end
    -- math.random is fine here: this is a user action, not a reproducible
    -- database operation, and avoids another large correlated SQL projection.
    math.randomseed(os.time() + #books)
    local book = books[math.random(#books)]
    self:showBookDetails(book)
end

function LibraryUI:showRoot()
    Debug.log("open library root")

    local rows = {
        {
            name = L("all_books"),
            mandatory_func = function() return tostring(self.repo:countBooks()) end,
            callback = function() self:showAllBooks() end,
        },
        {
            name = L("authors"),
            mandatory_func = function() return tostring(self.repo:countAuthors()) end,
            callback = function() self:showAuthors() end,
        },
        {
            name = L("series"),
            mandatory_func = function() return tostring(self.repo:countSeries()) end,
            callback = function() self:showSeries() end,
        },
        {
            name = L("titles"),
            mandatory_func = function() return tostring(self.repo:countBooks()) end,
            callback = function() self:showTitles() end,
        },
        {
            name = L("folders"),
            callback = function() self:showFolders() end,
        },
        {
            name = L("random_book"),
            callback = function() self:openRandomBook() end,
        },
        {
            name = L("data_filters"),
            callback = function() self:showDataFilters() end,
        },
        {
            name = L("scan_library"),
            callback = function() self.plugin:scanLibrary(false) end,
        },
    }

    local menu
    local items = {}
    for _, row in ipairs(rows) do
        items[#items + 1] = {
            text = row.name,
            mandatory_func = row.mandatory_func,
            callback = row.callback,
        }
    end

    menu = AlReaderCatalogMenu:new{
        title = L("library"),
        item_table = items,
        enable_search = false,
        show_back = false,
        show_more = false,
        footer_label = "",
    }
    self.plugin.library_menu = menu
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
end

return LibraryUI
