package.path = "./?.lua;" .. package.path

local State = require("state")

local s = State.new()
assert(s.current.mode == "start")
assert(s.current.scroll_index == 1)

s:setSearch("Азимов")
s:setScroll(17)
s:setSort("author", true)

s:push{
    mode = "authors",
    selected = "Азимов",
    scroll_index = 1,
}

assert(s.current.mode == "authors")
assert(s.current.selected == "Азимов")
assert(s.current.search == "Азимов")
assert(s.current.sort == "author")
assert(s.current.reverse == true)

s:setSearch("Айзек")
s:setScroll(9)

local restored = s:back()
assert(restored.mode == "start")
assert(restored.search == "Азимов")
assert(restored.scroll_index == 17)
assert(restored.sort == "author")
assert(restored.reverse == true)
assert(s:back() == nil)

print("test_state: PASS")
