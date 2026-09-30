local function slurp(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end
local bridge=slurp("safecardbridge.lua")
local list=slurp("alreaderbooklist.lua")
local ui=slurp("libraryui.lua")
assert(bridge:find("adaptiveProfile",1,true), "adaptive profile missing")
assert(bridge:find("libraryx_target_rows",1,true), "target rows not consumed by bridge")
assert(bridge:find("math.min(target_rows, item_count)",1,true), "short lists do not expand to fill viewport")
assert(not bridge:find("densityScale",1,true), "legacy hard-coded densityScale still present")
assert(list:find("libraryx_target_rows",1,true), "target rows not propagated")
assert(ui:find("genres = genres",1,true), "genres not supplied as dedicated metadata")
assert(bridge:find("copy.genres = meta.genres",1,true), "genres not overlaid into safe card metadata")
print("test_adaptive_cards_static: PASS")
