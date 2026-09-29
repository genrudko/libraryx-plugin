local function slurp(path)
    local f = assert(io.open(path, "r"))
    local s = f:read("*a")
    f:close()
    return s
end

local main = slurp("main.lua")
assert(not main:find("setPausedContinueText", 1, true))
assert(not main:find("setPausedAbortText", 1, true))
assert(main:find('Trapper:setPausedText(L("scan_paused"), L("abort"), L("continue"))', 1, true))
assert(main:find("xpcall", 1, true), "scan needs visible error boundary")
assert(main:find("refreshLibraryMenu", 1, true))

local ui = slurp("libraryui.lua")
assert(not ui:find('require("gettext")', 1, true))
assert(ui:find('mandatory_func', 1, true))
assert(ui:find('text_func', 1, true))
assert(ui:find('self.plugin.library_menu = menu', 1, true))

local i18n = slurp("libraryxi18n.lua")
for _, phrase in ipairs({
    "Все книги", "Авторы", "Серии", "Папки", "Недавние",
    "Сканировать библиотеку", "Папка библиотеки", "Отладка"
}) do
    assert(i18n:find(phrase, 1, true), "missing Russian translation: " .. phrase)
end

print("test_device_bugfix_static: PASS")
