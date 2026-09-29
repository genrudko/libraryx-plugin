local Menu = require("ui/widget/menu")
local ReaderUI = require("apps/reader/readerui")
local UIManager = require("ui/uimanager")
local LibraryRepo = require("libraryrepo")
local Debug = require("libraryxdebug")
local L = require("libraryxi18n").t

local LibraryUI = {}
LibraryUI.__index = LibraryUI

function LibraryUI.new(plugin, repo)
    return setmetatable({
        plugin = assert(plugin),
        repo = repo or LibraryRepo.new(),
        menus = {},
    }, LibraryUI)
end

local function percent_text(p)
    if type(p) ~= "number" then return "" end
    return string.format("%.1f%%", p * 100)
end

function LibraryUI:bookText(book)
    local line = book.title or book.path
    local info = {}
    if book.series and book.series ~= "" then
        local series = book.series
        if book.series_index then series = series .. " #" .. tostring(book.series_index) end
        info[#info + 1] = series
    end
    if book.format and book.format ~= "" then info[#info + 1] = book.format end
    local pct = percent_text(book.percent_finished)
    if pct ~= "" then info[#info + 1] = pct end
    if #info > 0 then
        line = line .. "\n" .. table.concat(info, " · ")
    end
    return line
end

function LibraryUI:openBook(menu, book)
    Debug.log("open book", book.path)
    UIManager:close(menu)
    UIManager:nextTick(function()
        ReaderUI:showReader(book.path)
    end)
end

function LibraryUI:showBooks(title, books)
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
    menu = Menu:new{
        title = title,
        item_table = items,
        is_borderless = true,
        covers_fullscreen = true,
    }
    self.menus[#self.menus + 1] = menu
    UIManager:show(menu)
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
                self:showBooks(L("all_books"), self.repo:listBooks(5000, 0))
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
                self:showBooks(L("recent"), self.repo:listRecent(100))
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
