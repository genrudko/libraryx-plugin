local function slurp(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end

local text=slurp("libraryxi18n.lua")
local en_start=assert(text:find("    en = {",1,true), "English table missing")
local ru_start=assert(text:find("    ru = {",1,true), "Russian table missing")
local en=text:sub(en_start,ru_start-1)
local lang_start=assert(text:find("\nlocal function language()",ru_start,true), "language function missing")
local ru=text:sub(ru_start,lang_start-1)

local function keys(section)
    local out={}
    for key in section:gmatch("\n%s*([%a_][%w_]*)%s*=") do out[key]=true end
    return out
end

local en_keys,ru_keys=keys(en),keys(ru)
for key in pairs(en_keys) do assert(ru_keys[key],"missing Russian key: "..key) end
for key in pairs(ru_keys) do assert(en_keys[key],"missing English key: "..key) end

for _,path in ipairs({
    "main.lua","libraryui.lua","alreaderbooklist.lua","alreadercatalogmenu.lua",
    "libraryxbookdetails.lua","libraryxsettingsui.lua","debugui.lua",
}) do
    local source=slurp(path)
    for key in source:gmatch('L%("([^"]+)"%)') do
        assert(en_keys[key],"missing English translation used by "..path..": "..key)
        assert(ru_keys[key],"missing Russian translation used by "..path..": "..key)
    end
end

assert(text:find('lang:sub(1, 2) == "ru"',1,true))
assert(text:find('return "en"',1,true))
print("test_i18n_static: PASS")
