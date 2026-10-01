local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local Settings = require("libraryxsettings")
local L = require("libraryxi18n").t
local Lifecycle = require("libraryxlifecycle")

local Updater = {}

local RELEASES_API = "https://api.github.com/repos/genrudko/libraryx-plugin/releases?per_page=100"
local RELEASES_PAGE = "https://github.com/genrudko/libraryx-plugin/releases"
local _cached_release
local _last_background_check = 0
local _background_in_flight = false
local BACKGROUND_INTERVAL = 6 * 60 * 60

local function pluginDir()
    local src = debug.getinfo(1, "S").source:match("@(.*)$")
    local dir = src and src:match("^(.*)/[^/]+%.lua$")
    if dir and dir ~= "" then return dir end
    local DataStorage = require("datastorage")
    return DataStorage:getDataDir() .. "/plugins/libraryx.koplugin"
end

local function installedVersion()
    local ok, meta = pcall(dofile, pluginDir() .. "/_meta.lua")
    return (ok and meta and meta.version) or "0.0.0"
end

local function parseVersion(value)
    local raw = tostring(value or ""):gsub("^v", "")
    local core, suffix = raw:match("^([^%-]+)%-?(.*)$")
    local nums = {}
    for part in tostring(core or ""):gmatch("(%d+)") do
        nums[#nums + 1] = tonumber(part) or 0
    end
    return nums, suffix or ""
end

function Updater._isNewer(candidate, installed)
    local a, ap = parseVersion(candidate)
    local b, bp = parseVersion(installed)
    for i = 1, math.max(#a, #b, 3) do
        local x, y = a[i] or 0, b[i] or 0
        if x ~= y then return x > y end
    end
    if ap == bp then return false end
    if ap == "" then return true end
    if bp == "" then return false end
    return ap > bp
end

local function isEligible(rel, channel)
    if type(rel) ~= "table" or rel.draft or not rel.tag_name then return false end
    if channel == "stable" and rel.prerelease then return false end
    return true
end

function Updater._selectRelease(releases, channel)
    local best
    for _, rel in ipairs(releases or {}) do
        if isEligible(rel, channel) then
            if not best or Updater._isNewer(rel.tag_name, best.tag_name) then
                best = rel
            end
        end
    end
    return best
end

local function assetURL(release)
    for _, asset in ipairs(release and release.assets or {}) do
        local name = tostring(asset.name or "")
        if name:match("%.koplugin%.zip$") then
            return asset.browser_download_url
        end
    end
end

local function fetchLatest()
    local version = installedVersion()
    local releases = require("libraryxhttp").getJSON(
        RELEASES_API, "KOReader-LibraryX/" .. version)
    if type(releases) ~= "table" then return nil end
    local release = Updater._selectRelease(releases, Settings.updateChannel())
    if release then _cached_release = release end
    return release
end

local function stripMarkdown(text)
    text = tostring(text or "")
    text = text:gsub("#+%s*", "")
    text = text:gsub("%*%*(.-)%*%*", "%1")
    text = text:gsub("`(.-)`", "%1")
    return text
end

local function safeRelativePath(path)
    path = tostring(path or "")
    if path == "" or path:sub(1, 1) == "/" or path:find("\\", 1, true) then
        return nil
    end
    for part in path:gmatch("[^/]+") do
        if part == "." or part == ".." or part == "" then return nil end
    end
    return path
end

local function purge(path)
    local lfs = require("libs/libkoreader-lfs")
    if not lfs.attributes(path, "mode") then return true end
    local ok_util, ffiUtil = pcall(require, "ffi/util")
    if not (ok_util and ffiUtil and ffiUtil.purgeDir) then
        return false, "directory cleanup unavailable"
    end
    return ffiUtil.purgeDir(path)
end

local function unpackStripRoot(zip_path, dest)
    local ok, Archiver = pcall(require, "ffi/archiver")
    if not (ok and Archiver and Archiver.Reader) then
        return false, "archive extractor unavailable"
    end
    local lfs = require("libs/libkoreader-lfs")
    if lfs.attributes(dest, "mode") then
        local cleaned, clean_err = purge(dest)
        if not cleaned then return false, clean_err end
    end
    if not lfs.mkdir(dest) then
        return false, "could not create staging directory"
    end

    local arc = Archiver.Reader:new()
    if not arc:open(zip_path) then
        local err = arc.err
        arc:close()
        purge(dest)
        return false, err or "could not open archive"
    end

    local extract_err
    local extracted = 0
    for entry in arc:iterate() do
        local rel = entry.path and entry.path:match("^[^/]+/(.+)$")
        if rel and rel ~= "" then
            rel = safeRelativePath(rel)
            if not rel then
                extract_err = "unsafe archive path"
                break
            end
            if not arc:extractToPath(entry.path, dest .. "/" .. rel) then
                extract_err = arc.err or "extract failed"
                break
            end
            extracted = extracted + 1
        elseif entry.path and entry.path:match("^[^/]+/$") then
            -- Archive root directory; nothing to extract directly.
        else
            extract_err = "unsafe archive path"
            break
        end
    end
    arc:close()

    if extract_err or extracted == 0 then
        purge(dest)
        return false, extract_err or "archive is empty"
    end
    if lfs.attributes(dest .. "/_meta.lua", "mode") ~= "file" then
        purge(dest)
        return false, "invalid LibraryX package"
    end
    return true
end

local function installStaged(zip_path, final_dir, expected_version)
    local lfs = require("libs/libkoreader-lfs")
    local stage = final_dir .. ".libraryx-update"
    local backup = final_dir .. ".libraryx-backup"

    local ok, err = purge(stage)
    if not ok then return false, err end
    ok, err = purge(backup)
    if not ok then return false, err end

    ok, err = unpackStripRoot(zip_path, stage)
    if not ok then return false, err end

    local meta_ok, meta = pcall(dofile, stage .. "/_meta.lua")
    if not (meta_ok and type(meta) == "table" and meta.name == "libraryx"
            and type(meta.version) == "string") then
        purge(stage)
        return false, "invalid LibraryX metadata"
    end
    if expected_version and meta.version ~= expected_version then
        purge(stage)
        return false, string.format(
            "package version mismatch: expected %s, got %s",
            tostring(expected_version), tostring(meta.version))
    end

    if lfs.attributes(final_dir, "mode") ~= "directory" then
        purge(stage)
        return false, "running plugin directory is missing"
    end

    local renamed, rename_err = os.rename(final_dir, backup)
    if not renamed then
        purge(stage)
        return false, rename_err or "could not create update backup"
    end

    renamed, rename_err = os.rename(stage, final_dir)
    if not renamed then
        local rolled_back, rollback_err = os.rename(backup, final_dir)
        purge(stage)
        if not rolled_back then
            return false, string.format(
                "update failed (%s); rollback failed (%s)",
                tostring(rename_err), tostring(rollback_err))
        end
        return false, rename_err or "could not activate staged update"
    end

    local cleaned, clean_err = purge(backup)
    if not cleaned then
        -- The update is already active. Keep a non-.koplugin backup rather
        -- than rolling back a valid install just because cleanup failed.
        return true, "backup cleanup failed: " .. tostring(clean_err)
    end
    return true
end

Updater._safeRelativePath = safeRelativePath
Updater._unpackStripRoot = unpackStripRoot
Updater._installStaged = installStaged

function Updater.getInstalledVersion()
    return installedVersion()
end

function Updater.getAvailableUpdate()
    if _cached_release and Updater._isNewer(
            _cached_release.tag_name, installedVersion()) then
        return _cached_release.tag_name:gsub("^v", "")
    end
end

function Updater.openReleasesPage()
    if Device.canOpenLink and Device:canOpenLink() then
        Device:openLink(RELEASES_PAGE)
    else
        UIManager:show(InfoMessage:new{
            text = L("updates_releases_url") .. "\n" .. RELEASES_PAGE,
            timeout = 4,
        })
    end
end

local function gateOnConnection(retry)
    local NetworkMgr = require("ui/network/manager")
    if NetworkMgr:isConnected() then return false end
    NetworkMgr:runWhenConnected(function()
        if NetworkMgr:isConnected() then retry() end
    end)
    return true
end

function Updater.install(release)
    release = release or _cached_release
    if not release then return end
    local url = assetURL(release)
    local new_version = tostring(release.tag_name or ""):gsub("^v", "")
    if not url then
        UIManager:show(InfoMessage:new{
            text = L("updates_no_download"),
            timeout = 3,
        })
        return
    end
    if gateOnConnection(function() Updater.install(release) end) then return end

    UIManager:show(InfoMessage:new{
        text = L("updates_downloading"),
        timeout = 1,
    })
    UIManager:scheduleIn(0.1, function()
        local DataStorage = require("datastorage")
        local lfs = require("libs/libkoreader-lfs")
        local cache_dir = DataStorage:getSettingsDir() .. "/libraryx_update"
        if lfs.attributes(cache_dir, "mode") ~= "directory" then
            lfs.mkdir(cache_dir)
        end
        local zip_path = cache_dir .. "/libraryx.koplugin.zip"
        if not require("libraryxhttp").download(
                url, zip_path, "KOReader-LibraryX/" .. installedVersion()) then
            UIManager:show(InfoMessage:new{
                text = L("updates_download_failed"),
                timeout = 4,
            })
            return
        end
        local ok, err = installStaged(zip_path, pluginDir(), new_version)
        pcall(os.remove, zip_path)
        if not ok then
            UIManager:show(InfoMessage:new{
                text = L("updates_install_failed") .. ": " .. tostring(err),
                timeout = 5,
            })
            return
        end
        local confirm = ConfirmBox:new{
            text = string.format(
                L("updates_installed_restart"),
                new_version),
            ok_text = L("restart"),
            ok_callback = function() UIManager:restartKOReader() end,
        }
        Lifecycle.track(confirm)
        UIManager:show(confirm)
    end)
end

function Updater.check()
    if gateOnConnection(function() Updater.check() end) then return end
    UIManager:show(InfoMessage:new{
        text = L("updates_checking"),
        timeout = 1,
    })
    UIManager:scheduleIn(0.1, function()
        local release = fetchLatest()
        if not release then
            UIManager:show(InfoMessage:new{
                text = L("updates_check_failed"),
                timeout = 3,
            })
            return
        end
        local current = installedVersion()
        if not Updater._isNewer(release.tag_name, current) then
            UIManager:show(InfoMessage:new{
                text = string.format(L("updates_up_to_date"), current),
                timeout = 3,
            })
            return
        end

        local viewer
        viewer = TextViewer:new{
            title = L("updates_available"),
            text = string.format(
                "%s: v%s\n%s: %s\n\n%s",
                L("installed_version"), current,
                L("available_version"), release.tag_name,
                stripMarkdown(release.body)),
            add_default_buttons = false,
            buttons_table = {
                {
                    {
                        text = L("close"),
                        callback = function() UIManager:close(viewer) end,
                    },
                    {
                        text = L("update_and_restart"),
                        callback = function()
                            UIManager:close(viewer)
                            Updater.install(release)
                        end,
                    },
                },
            },
        }
        Lifecycle.track(viewer)
        UIManager:show(viewer)
    end)
end

function Updater.checkBackground()
    if not Settings.autoUpdateCheck() or _background_in_flight then return end
    local now = os.time()
    if now - _last_background_check < BACKGROUND_INTERVAL then return end
    local NetworkMgr = require("ui/network/manager")
    if not NetworkMgr:isConnected() then return end

    _last_background_check = now
    _background_in_flight = true
    UIManager:scheduleIn(0.1, function()
        local release = fetchLatest()
        _background_in_flight = false
        if release and Updater._isNewer(release.tag_name, installedVersion()) then
            local Notification = require("ui/widget/notification")
            Notification:notify(
                string.format(
                    L("updates_background_available"),
                    release.tag_name:gsub("^v", "")),
                Notification.SOURCE_ALWAYS_SHOW)
        end
    end)
end

return Updater
