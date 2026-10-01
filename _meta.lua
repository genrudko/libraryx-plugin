local override = G_reader_settings
    and G_reader_settings:readSetting("libraryx_language")
    or "system"
override = tostring(override or "system"):lower()
local lang = override ~= "system" and override
    or (G_reader_settings and G_reader_settings:readSetting("language") or "en")
lang = tostring(lang or "en"):lower()

local description
if lang:sub(1, 2) == "ru" then
    description = "Индексированная библиотека в стиле AlReaderX для KOReader."
else
    description = "AlReaderX-style indexed library for KOReader."
end

return {
    name = "libraryx",
    fullname = "LibraryX",
    version = "0.4.7-beta",
    description = description,
}
