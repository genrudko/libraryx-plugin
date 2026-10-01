local function slurp(path)
    local f=assert(io.open(path,"r")); local s=f:read("*a"); f:close(); return s
end

local bridge=slurp("safecardbridge.lua")
assert(bridge:find("withAdaptiveFonts",1,true), "shared adaptive-font wrapper missing")
assert(bridge:find("local original_update = modules.CoverMenu.updateItems",1,true), "CoverMenu update wrapper missing")
assert(bridge:find("UIManager:unschedule(original_action)",1,true), "upstream unscaled background action not replaced")
assert(bridge:find("self.items_update_action = wrapped_action",1,true), "scaled background action not installed")
assert(bridge:find("withAdaptiveFonts(self, original_action)",1,true), "background item:update path is not scaled")
assert(bridge:find("UIManager:scheduleIn(1, wrapped_action)",1,true), "scaled background action not scheduled")
print("test_background_index_scaling_static: PASS")
