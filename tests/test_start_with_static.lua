local function slurp(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end
local main=slurp("main.lua")
assert(main:find('START_WITH_VALUE = "libraryx"',1,true))
assert(main:find("function LibraryX:registerStartWith",1,true))
assert(main:find("getStartWithMenuTable",1,true))
assert(main:find('text = L("libraryx")',1,true))
assert(main:find('radio = true',1,true))
assert(main:find('start_with_libraryx',1,true))
assert(main:find("function LibraryX:onShow",1,true))
assert(main:find("expect_initial_takeover",1,true))
assert(main:find("initial_takeover_done",1,true))
print("test_start_with_static: PASS")
