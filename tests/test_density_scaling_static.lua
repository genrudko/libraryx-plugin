local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

local bridge=slurp("safecardbridge.lua")
for _, needle in ipairs({
    'function SafeCardBridge.densityScale',
    'if count == 6 then return 0.88 end',
    'if count == 7 then return 0.86 end',
    'if count == 8 then return 0.84 end',
    'if count == 9 then return 0.82 end',
    'return 0.80',
    'Font.getFace = function',
    'math.floor(size * density + 0.5)',
    'Font.getFace = original_get_face',
}) do
    assert(bridge:find(needle,1,true), "missing density scaling: "..needle)
end

local list=slurp("alreaderbooklist.lua")
assert(list:find("local MAX_CARDS_PER_PAGE = 10",1,true))
for n=3,10 do
    assert(list:find("option("..n..")",1,true), "missing density option "..n)
end
assert(list:find('L("books_per_screen")',1,true))

print("test_density_scaling_static: PASS")
