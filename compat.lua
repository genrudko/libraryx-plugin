local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local TextViewer = require("ui/widget/textviewer")
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

local function first_existing_history_file(ReadHistory)
    for _, item in ipairs(ReadHistory.hist or {}) do
        if item.select_enabled and item.file then
            return item.file, item.time
        end
    end
end

function Compat.run(plugin)
    local results = {}
    local passed, failed = 0, 0
    local function probe(name, fn)
        local ok, value = check(results, name, fn)
        if ok then passed = passed + 1 else failed = failed + 1 end
        return ok, value
    end

    local _, SQ3 = probe("lua-ljsqlite3", function()
        return require("lua-ljsqlite3/init")
    end)

    probe("DataStorage settings dir", function()
        local p = DataStorage:getSettingsDir()
        assert(type(p) == "string" and #p > 0, "empty settings directory")
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

    if SQ3 then
        probe("SQLite create/write/read", function()
            local path = DataStorage:getSettingsDir() .. "/libraryx_m0_probe.sqlite3"
            os.remove(path)
            local db = SQ3.open(path)
            db:exec([[
                CREATE TABLE probe (
                    id INTEGER PRIMARY KEY,
                    value TEXT NOT NULL
                );
                INSERT INTO probe(value) VALUES ('LIBRARYX_M0_OK');
            ]])
            local value = db:rowexec("SELECT value FROM probe WHERE id=1;")
            db:close()
            os.remove(path)
            assert(value == "LIBRARYX_M0_OK", "unexpected SQLite round-trip value")
            return "round-trip OK"
        end)
    end

    if ReadHistory and BookList then
        local file, ts = first_existing_history_file(ReadHistory)
        if file then
            probe("Reading state from real history item", function()
                local info = BookList.getBookInfo(file)
                local pct = info.percent_finished
                local status = BookList.getBookStatus(file)
                return string.format("%s; progress=%s; last_read=%s",
                    tostring(status),
                    pct and string.format("%.2f%%", pct * 100) or "n/a",
                    ts and os.date("%Y-%m-%d %H:%M:%S", ts) or "n/a")
            end)

            probe("Cached metadata from real history item", function()
                local props = plugin.ui.bookinfo:getDocProps(file, nil, true)
                assert(type(props) == "table", "metadata result is not a table")
                return props.display_title or props.title or "(metadata present)"
            end)
        else
            results[#results + 1] = "[SKIP] Real history item — no existing readable history entry"
        end
    end

    local header = string.format(
        "LibraryX M0 compatibility probe\nKOReader target API verification\n\nPASS: %d    FAIL: %d\n\n",
        passed, failed
    )
    local footer = failed == 0
        and "\n\nRESULT: M0 API compatibility PASS"
        or "\n\nRESULT: M0 API compatibility FAIL — send this report before proceeding."

    UIManager:show(TextViewer:new{
        title = _("LibraryX compatibility"),
        text = header .. table.concat(results, "\n") .. footer,
    })

    return failed == 0, results
end

return Compat
