local Settings = {}

local PREFIX = "libraryx_"
local LEGACY_CARDS_KEY = "libraryx_cards_per_page"

local specs = {
    language = { key = PREFIX .. "language", default = "system" },
    list_density = { key = PREFIX .. "list_density", default = "auto" },
    list_font_scale = { key = PREFIX .. "list_font_scale", default = 100, min = 80, max = 120 },
    list_show_genres = { key = PREFIX .. "list_show_genres", default = true },
    list_show_language = { key = PREFIX .. "list_show_language", default = true },
    list_show_series_index = { key = PREFIX .. "list_show_series_index", default = true },
    list_show_file_info = { key = PREFIX .. "list_show_file_info", default = true },
    details_body_scale = { key = PREFIX .. "details_body_scale", default = 90, min = 70, max = 130 },
    details_title_scale = { key = PREFIX .. "details_title_scale", default = 100, min = 80, max = 130 },
    details_cover_scale = { key = PREFIX .. "details_cover_scale", default = 100, min = 60, max = 110 },
    details_show_genres = { key = PREFIX .. "details_show_genres", default = true },
    details_show_metadata = { key = PREFIX .. "details_show_metadata", default = true },
    details_show_path = { key = PREFIX .. "details_show_path", default = true },
    show_alphabet = { key = PREFIX .. "show_alphabet", default = true },
    scan_on_open = { key = PREFIX .. "scan_on_open", default = false },
    update_auto_check = { key = PREFIX .. "update_auto_check", default = true },
    update_channel = { key = PREFIX .. "update_channel", default = "beta" },
}

local function clamp(value, minv, maxv)
    value = tonumber(value) or minv
    return math.max(minv, math.min(maxv, value))
end

local function normalize(name, value)
    local spec = assert(specs[name], "unknown LibraryX setting: " .. tostring(name))
    if name == "list_density" then
        if value == "auto" or value == nil then return "auto" end
        local n = tonumber(value)
        if not n then return "auto" end
        return math.max(3, math.min(10, math.floor(n + 0.5)))
    end
    if name == "language" then
        value = tostring(value or "system"):lower()
        if value ~= "ru" and value ~= "en" then return "system" end
        return value
    end
    if name == "update_channel" then
        value = tostring(value or "beta"):lower()
        if value ~= "stable" then return "beta" end
        return value
    end
    if spec.min then
        return clamp(value, spec.min, spec.max)
    end
    if type(spec.default) == "boolean" then
        return value == true
    end
    return value
end

function Settings.get(name)
    local spec = assert(specs[name], "unknown LibraryX setting: " .. tostring(name))
    local value = G_reader_settings and G_reader_settings:readSetting(spec.key) or nil
    if value == nil and name == "list_density" and G_reader_settings then
        value = G_reader_settings:readSetting(LEGACY_CARDS_KEY)
    end
    if value == nil then value = spec.default end
    return normalize(name, value)
end

function Settings.set(name, value)
    local spec = assert(specs[name], "unknown LibraryX setting: " .. tostring(name))
    value = normalize(name, value)
    if G_reader_settings then
        G_reader_settings:saveSetting(spec.key, value)
        if name == "list_density" then
            if value == "auto" then
                G_reader_settings:delSetting(LEGACY_CARDS_KEY)
            else
                G_reader_settings:saveSetting(LEGACY_CARDS_KEY, value)
            end
        end
        G_reader_settings:flush()
    end
    return value
end

function Settings.resetAll()
    if not G_reader_settings then return end
    for _, spec in pairs(specs) do
        G_reader_settings:delSetting(spec.key)
    end
    G_reader_settings:delSetting(LEGACY_CARDS_KEY)
    G_reader_settings:flush()
end

function Settings.listDensity()
    local value = Settings.get("list_density")
    return value == "auto" and nil or value
end

function Settings.isAutoDensity() return Settings.get("list_density") == "auto" end
function Settings.fontScale() return Settings.get("list_font_scale") end
function Settings.showGenres() return Settings.get("list_show_genres") end
function Settings.showLanguage() return Settings.get("list_show_language") end
function Settings.showSeriesIndex() return Settings.get("list_show_series_index") end
function Settings.showFileInfo() return Settings.get("list_show_file_info") end
function Settings.detailsBodyScale() return Settings.get("details_body_scale") end
function Settings.detailsTitleScale() return Settings.get("details_title_scale") end
function Settings.detailsCoverScale() return Settings.get("details_cover_scale") end
function Settings.detailsShowGenres() return Settings.get("details_show_genres") end
function Settings.detailsShowMetadata() return Settings.get("details_show_metadata") end
function Settings.detailsShowPath() return Settings.get("details_show_path") end
function Settings.showAlphabet() return Settings.get("show_alphabet") end
function Settings.scanOnOpen() return Settings.get("scan_on_open") end
function Settings.autoUpdateCheck() return Settings.get("update_auto_check") end
function Settings.updateChannel() return Settings.get("update_channel") end
function Settings.language() return Settings.get("language") end

return Settings
