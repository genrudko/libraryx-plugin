local function slurp(path)
    local f=assert(io.open(path,"r"))
    local s=f:read("*a")
    f:close()
    return s
end

for _, path in ipairs({"alreaderbooklist.lua", "alreadercatalogmenu.lua"}) do
    local s=slurp(path)
    assert(s:find("WidgetContainer.clear(self.return_button, true)",1,true),
        path .. ": stock return overlay not removed")
    assert(s:find("steals taps from our footer",1,true),
        path .. ": regression rationale missing")
end

print("test_footer_hitbox_static: PASS")
