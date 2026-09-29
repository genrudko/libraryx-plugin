local DataStorage = require("datastorage")
local Device = require("device")
local SQ3 = require("lua-ljsqlite3/init")

local Storage = {}
Storage.__index = Storage

local SCHEMA_VERSION = 2

local SCHEMA = [[
CREATE TABLE IF NOT EXISTS meta (
    key TEXT PRIMARY KEY,
    value TEXT
);

CREATE TABLE IF NOT EXISTS books (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    path TEXT NOT NULL UNIQUE,
    directory TEXT NOT NULL,
    filename TEXT NOT NULL,
    filesize INTEGER,
    filemtime INTEGER,
    scanned_at INTEGER NOT NULL,
    scan_token INTEGER,
    title TEXT,
    sort_title TEXT,
    language TEXT,
    series TEXT,
    series_index REAL,
    description TEXT,
    format TEXT,
    active INTEGER NOT NULL DEFAULT 1,
    last_read_at INTEGER,
    percent_finished REAL,
    reading_status TEXT
);

CREATE TABLE IF NOT EXISTS authors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    sort_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS book_authors (
    book_id INTEGER NOT NULL,
    author_id INTEGER NOT NULL,
    ordinal INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(book_id, author_id),
    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
    FOREIGN KEY(author_id) REFERENCES authors(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS genres (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    sort_name TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS book_genres (
    book_id INTEGER NOT NULL,
    genre_id INTEGER NOT NULL,
    PRIMARY KEY(book_id, genre_id),
    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
    FOREIGN KEY(genre_id) REFERENCES genres(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS collections (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL UNIQUE,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS book_collections (
    book_id INTEGER NOT NULL,
    collection_id INTEGER NOT NULL,
    PRIMARY KEY(book_id, collection_id),
    FOREIGN KEY(book_id) REFERENCES books(id) ON DELETE CASCADE,
    FOREIGN KEY(collection_id) REFERENCES collections(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS scan_roots (
    path TEXT PRIMARY KEY,
    enabled INTEGER NOT NULL DEFAULT 1,
    last_scan_at INTEGER
);

CREATE INDEX IF NOT EXISTS idx_books_active_title
    ON books(active, sort_title, title);
CREATE INDEX IF NOT EXISTS idx_books_series
    ON books(active, series, series_index, sort_title);
CREATE INDEX IF NOT EXISTS idx_books_last_read
    ON books(active, last_read_at DESC);
CREATE INDEX IF NOT EXISTS idx_books_language
    ON books(active, language);
CREATE INDEX IF NOT EXISTS idx_books_format
    ON books(active, format);
CREATE INDEX IF NOT EXISTS idx_books_scan_token
    ON books(scan_token, active);
CREATE INDEX IF NOT EXISTS idx_authors_sort
    ON authors(sort_name, name);
CREATE INDEX IF NOT EXISTS idx_book_authors_author
    ON book_authors(author_id, book_id);
CREATE INDEX IF NOT EXISTS idx_book_genres_genre
    ON book_genres(genre_id, book_id);
]]

function Storage.new(path)
    return setmetatable({
        path = path or (DataStorage:getSettingsDir() .. "/libraryx.sqlite3"),
        db = nil,
    }, Storage)
end

function Storage:open()
    if self.db then return self.db end
    self.db = SQ3.open(self.path)
    if Device:canUseWAL() then
        self.db:exec("PRAGMA journal_mode=WAL;")
    else
        self.db:exec("PRAGMA journal_mode=TRUNCATE;")
    end
    self.db:exec("PRAGMA foreign_keys=ON;")
    self.db:exec(SCHEMA)
    self.db:exec(string.format("PRAGMA user_version=%d;", SCHEMA_VERSION))
    return self.db
end

function Storage:close()
    if self.db then
        self.db:close()
        self.db = nil
    end
end

function Storage:selfTest()
    local db = self:open()
    db:exec("BEGIN IMMEDIATE;")
    db:exec("INSERT OR REPLACE INTO meta(key, value) VALUES ('m0_probe', 'ok');")
    local value = db:rowexec("SELECT value FROM meta WHERE key='m0_probe';")
    db:exec("DELETE FROM meta WHERE key='m0_probe';")
    db:exec("COMMIT;")
    assert(value == "ok", "LibraryX storage self-test failed")
    return true
end

return Storage
