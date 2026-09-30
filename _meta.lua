local lang = G_reader_settings
    and G_reader_settings:readSetting("language")
    or "en"
lang = tostring(lang or "en"):lower()

local description
if lang:sub(1, 2) == "ru" then
    description = "Индексированная библиотека в стиле AlReaderX для KOReader."
else
    description = "AlReaderX-style indexed library for KOReader."
end

return {
    fullname = "LibraryX",
    description = description,
}
