package.path = "./?.lua;" .. package.path
local Model = require("model")

local a = Model.splitMultiValue("Иванов\nПетров\nИванов\n")
assert(#a == 2)
assert(a[1] == "Иванов")
assert(a[2] == "Петров")
assert(Model.fileFormat("/books/a.fb2") == "FB2")
assert(Model.filename("/books/a.fb2") == "a.fb2")
assert(Model.directory("/books/a.fb2") == "/books")

local b = Model.bookRecord(
    "/books/Тест.fb2",
    { size = 742000, modification = 123 },
    {
        title = "Бастард Императора",
        authors = "Орлов Андрей",
        series = "Бастард Императора",
        series_index = "1.0",
        language = "ru",
        keywords = "фантастика\nДругое",
    },
    { status = "reading", percent_finished = 0.2094, last_read_at = 456 },
    789
)

assert(b.title == "Бастард Императора")
assert(b.series_index == 1)
assert(b.format == "FB2")
assert(b.percent_finished == 0.2094)
assert(b.added_at == 789)
assert(#b.authors == 1 and b.authors[1] == "Орлов Андрей")
assert(#b.genres == 2 and b.genres[1] == "фантастика")
print("test_model: PASS")
