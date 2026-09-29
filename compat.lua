local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local TextViewer = require("ui/widget/textviewer")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Compat = {}

local function check(results, name, fn)
    local ok, value = pcall(fn)
    if ok then
        results[#results + 1] = string.format("[PASS] %s%s", name,
            value ~= nil and (" — " .. tostring(value)) or "")
        return true, value
    end
    results[#results + 1] = string.format("[FAIL] %s — %s", name, tostring(value))
    return false, value
end

local function remove_if_exists(path)
    if lfs.attributes(path, "mode") then
        local ok, err = os.remove(path)
        if not ok then
            return false, err
        end
    end
    return true
end

local function first_history_item_with_progress(ReadHistory, BookList)
    local checked = 0
    for _, item in ipairs(ReadHistory.hist or {}) do
        if item.select_enabled and item.file then
            checked = checked + 1
            local ok, info = pcall(BookList.getBookInfo, item.file)
            if ok and info and info.been_opened and type(info.percent_finished) == "number" then
                return item.file, item.time, info
            end
            if checked >= 100 then
                break
            end
        end
    end
end

local function has_cached_metadata(props)
    return props and (
        props.title
        or props.authors
        or props.series
        or props.language
        or props.keywords
        or props.description
    )
end

local function first_history_item_with_cached_metadata(ReadHistory, bookinfo)
    local checked = 0
    for _, item in ipairs(ReadHistory.hist or {}) do
        if item.select_enabled and item.file then
            checked = checked + 1
            local ok, props = pcall(bookinfo.getDocProps, bookinfo, item.file, nil, true)
            if ok and has_cached_metadata(props) then
                return item.file, props
            end
            if checked >= 100 then
                break
            end
        end
    end
end

function Compat.run(plugin)
    local results = {}
    local passed, failed, skipped = 0, 0, 0
    local function probe(name, fn)
        local ok, value = check(results, name, fn)
        if ok then passed = passed + 1 else failed = failed + 1 end
        return ok, value
    end
    local function skip(name, reason)
        skipped = skipped + 1
        results[#results + 1] = string.format("[SKIP] %s — %s", name, reason)
    end

    local sq3_ok, SQ3 = probe("lua-ljsqlite3", function()
        return require("lua-ljsqlite3/init")
    end)

    local settings_dir
    local settings_ok = probe("DataStorage settings dir", function()
        local p = DataStorage:getSettingsDir()
        assert(type(p) == "string" and #p > 0, "empty settings directory")
        settings_dir = p
        return p
    end)

    local BookList
    probe("BookList API", function()
        local mod = require("ui/widget/booklist")
        assert(type(mod.getBookInfo) == "function", "getBookInfo missing")
        assert(type(mod.getBookStatus) == "function", "getBookStatus missing")
        BookList = mod
        return "progress/status available"
    end)

    local ReadHistory
    probe("ReadHistory API", function()
        local mod = require("readhistory")
        assert(type(mod.hist) == "table", "history table missing")
        ReadHistory = mod
        return string.format("%d history entries", #mod.hist)
    end)

    probe("FileManager BookInfo API", function()
        local mod = require("apps/filemanager/filemanagerbookinfo")
        assert(type(mod.getDocProps) == "function", "getDocProps missing")
        assert(type(mod.getCoverImage) == "function", "getCoverImage missing")
        return "metadata/cover methods available"
    end)

    probe("ReaderUI API", function()
        local mod = require("apps/reader/readerui")
        assert(type(mod.showReader) == "function", "showReader missing")
        return "showReader available"
    end)

    probe("DocumentRegistry API", function()
        local mod = require("document/documentregistry")
        assert(type(mod.hasProvider) == "function", "hasProvider missing")
        return "provider lookup available"
    end)

    probe("FileManager ui.bookinfo", function()
        assert(plugin.ui and plugin.ui.bookinfo, "ui.bookinfo unavailable")
        assert(type(plugin.ui.bookinfo.getDocProps) == "function", "ui.bookinfo:getDocProps missing")
        return "live FileManager metadata facade available"
    end)

    if sq3_ok and settings_ok and SQ3 and settings_dir then
        probe("SQLite create/write/read/cleanup", function()
            local path = settings_dir .. "/libraryx_m0_probe.sqlite3"
            local removed, remove_err = remove_if_exists(path)
            assert(removed, "pre-cleanup failed: " .. tostring(remove_err))

            local db
            local body_ok, body_err = pcall(function()
                db = SQ3.open(path)
                db:exec([[
                    CREATE TABLE probe (
                        id INTEGER PRIMARY KEY,
                        value TEXT NOT NULL
                    );
                    INSERT INTO probe(value) VALUES ('LIBRARYX_M0_OK');
                ]])
                local value = db:rowexec("SELECT value FROM probe WHERE id=1;")
                assert(value == "LIBRARYX_M0_OK", "unexpected SQLite round-trip value")
            end)

            local close_ok, close_err = true, nil
            if db then
                close_ok, close_err = pcall(function()
                    db:close()
                end)
            end
            removed, remove_err = remove_if_exists(path)

            if not body_ok then
                error(body_err)
            end
            assert(close_ok, "database close failed: " .. tostring(close_err))
            assert(removed, "cleanup failed: " .. tostring(remove_err))
            return "round-trip and cleanup OK"
        end)
    end

    if ReadHistory and BookList then
        local file, ts, info = first_history_item_with_progress(ReadHistory, BookList)
        if file then
            probe("Reading progress from real history item", function()
                local status = BookList.getBookStatus(file)
                return string.format("%s; progress=%.2f%%; last_read=%s",
                    tostring(status),
                    info.percent_finished * 100,
                    ts and os.date("%Y-%m-%d %H:%M:%S", ts) or "n/a")
            end)
        else
            skip("Reading progress from real history item",
                "no readable history item with a numeric percent_finished in first 100 entries")
        end

        if plugin.ui and plugin.ui.bookinfo then
            local metadata_file, props = first_history_item_with_cached_metadata(
                ReadHistory, plugin.ui.bookinfo)
            if metadata_file then
                probe("Cached metadata from real history item", function()
                    return props.title or props.authors or props.series
                        or props.language or props.keywords or "(cached metadata present)"
                end)
            else
                skip("Cached metadata from real history item",
                    "no history item with real cached/sidecar metadata in first 100 entries")
            end
        end
    end

    local header = string.format(
        "LibraryX M0 compatibility probe\nKOReader target API verification\n\nPASS: %d    FAIL: %d    SKIP: %d\n\n",
        passed, failed, skipped
    )
    local footer
    if failed > 0 then
        footer = "\n\nRESULT: M0 API compatibility FAIL — send this report before proceeding."
    elseif skipped > 0 then
        footer = "\n\nRESULT: M0 API compatibility PARTIAL — one or more real-data checks were not verified."
    else
        footer = "\n\nRESULT: M0 API compatibility PASS"
    end

    UIManager:show(TextViewer:new{
        title = _("LibraryX compatibility"),
        text = header .. table.concat(results, "\n") .. footer,
    })

    return failed == 0 and skipped == 0, results
end

return Compat
