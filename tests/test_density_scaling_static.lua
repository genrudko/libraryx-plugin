local function slurp(path)
 local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end
local bridge=slurp("safecardbridge.lua")
for _,needle in ipairs({"function SafeCardBridge.adaptiveProfile","row_height","local ratio =","math.min(target_rows, item_count)","Font.getFace = function","math.floor(size * density + 0.5)","Font.getFace = original_get_face"}) do assert(bridge:find(needle,1,true),"missing adaptive density behavior: "..needle) end
assert(not bridge:find("densityScale",1,true))
local list=slurp("alreaderbooklist.lua")
assert(list:find("local MAX_CARDS_PER_PAGE = 10",1,true)); assert(list:find("libraryx_target_rows",1,true))
for n=3,10 do assert(list:find("option("..n..")",1,true),"missing density option "..n) end
print("test_density_scaling_static: PASS")
