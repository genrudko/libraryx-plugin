local Storage = require("storage")

local LibraryRepo = {}
LibraryRepo.__index = LibraryRepo

function LibraryRepo.new(storage)
    return setmetatable({
        storage = storage or Storage.new(),
    }, LibraryRepo)
end

local function step_done(stmt, ...)
    stmt:reset():bind(...):step()
end


local function collect_rows(stmt, map)
    local out = {}
    while true do
        local row = stmt:step()
        if not row then break end
        out[#out + 1] = map(row)
    end
    return out
end


function LibraryRepo:upsertBook(book)
    local db = self.storage:open()
    db:exec("BEGIN IMMEDIATE;")
    local ok, err = pcall(function()
        local stmt = db:prepare([[
            INSERT INTO books (
                path, directory, filename, filesize, filemtime, scanned_at, scan_token,
                metadata_version, added_at, title, sort_title, language, series, series_index, description,
                format, active, last_read_at, percent_finished, reading_status
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                directory=excluded.directory,
                filename=excluded.filename,
                filesize=excluded.filesize,
                filemtime=excluded.filemtime,
                scanned_at=excluded.scanned_at,
                scan_token=excluded.scan_token,
                metadata_version=excluded.metadata_version,
                title=excluded.title,
                sort_title=excluded.sort_title,
                language=excluded.language,
                series=excluded.series,
                series_index=excluded.series_index,
                description=excluded.description,
                format=excluded.format,
                active=1,
                last_read_at=excluded.last_read_at,
                percent_finished=excluded.percent_finished,
                reading_status=excluded.reading_status;
        ]])
        step_done(stmt,
            book.path, book.directory, book.filename, book.filesize, book.filemtime,
            book.scanned_at, book.scan_token, book.metadata_version, book.added_at,
            book.title, book.sort_title, book.language,
            book.series, book.series_index, book.description, book.format, book.active,
            book.last_read_at, book.percent_finished, book.reading_status)

        local id_stmt = db:prepare("SELECT id FROM books WHERE path = ?;")
        local id_row = id_stmt:reset():bind(book.path):step()
        assert(id_row and id_row[1], "book row missing after upsert")
        local book_id = id_row[1]

        step_done(db:prepare("DELETE FROM book_authors WHERE book_id = ?;"), book_id)
        local insert_author = db:prepare([[
            INSERT INTO authors(name, sort_name) VALUES (?, ?)
            ON CONFLICT(name) DO NOTHING;
        ]])
        local author_id_stmt = db:prepare("SELECT id FROM authors WHERE name = ?;")
        local link_author = db:prepare([[
            INSERT OR REPLACE INTO book_authors(book_id, author_id, ordinal)
            VALUES (?, ?, ?);
        ]])
        for ordinal, name in ipairs(book.authors or {}) do
            step_done(insert_author, name, name:lower())
            local row = author_id_stmt:reset():bind(name):step()
            assert(row and row[1], "author id missing")
            step_done(link_author, book_id, row[1], ordinal)
        end

        step_done(db:prepare("DELETE FROM book_genres WHERE book_id = ?;"), book_id)
        local insert_genre = db:prepare([[
            INSERT INTO genres(name, sort_name) VALUES (?, ?)
            ON CONFLICT(name) DO NOTHING;
        ]])
        local genre_id_stmt = db:prepare("SELECT id FROM genres WHERE name = ?;")
        local link_genre = db:prepare([[
            INSERT OR REPLACE INTO book_genres(book_id, genre_id)
            VALUES (?, ?);
        ]])
        for _, name in ipairs(book.genres or {}) do
            step_done(insert_genre, name, name:lower())
            local row = genre_id_stmt:reset():bind(name):step()
            assert(row and row[1], "genre id missing")
            step_done(link_genre, book_id, row[1])
        end
    end)
    if ok then
        db:exec("COMMIT;")
    else
        pcall(function() db:exec("ROLLBACK;") end)
        error(err)
    end
end


function LibraryRepo:startScan(root_path, started_at)
    local db = self.storage:open()
    db:exec("BEGIN IMMEDIATE;")
    local ok, token_or_err = pcall(function()
        local current = tonumber(db:rowexec(
            "SELECT value FROM meta WHERE key='scan_generation';")) or 0
        local token = current + 1
        local gen_stmt = db:prepare([[
            INSERT INTO meta(key, value) VALUES ('scan_generation', ?)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value;
        ]])
        step_done(gen_stmt, tostring(token))
        local root_stmt = db:prepare([[
            INSERT INTO scan_roots(path, enabled, last_scan_at)
            VALUES (?, 1, ?)
            ON CONFLICT(path) DO UPDATE SET enabled=1, last_scan_at=excluded.last_scan_at;
        ]])
        step_done(root_stmt, root_path, started_at)
        return token
    end)
    if ok then
        db:exec("COMMIT;")
        return token_or_err
    end
    pcall(function() db:exec("ROLLBACK;") end)
    error(token_or_err)
end

function LibraryRepo:touchUnchanged(path, attrs, scan_token, scanned_at, read_state)
    local db = self.storage:open()
    local stmt = db:prepare([[
        UPDATE books
        SET filesize=?, filemtime=?, scanned_at=?, scan_token=?, active=1,
            last_read_at=?, percent_finished=?, reading_status=?
        WHERE path=?;
    ]])
    step_done(stmt,
        tonumber(attrs.size) or 0,
        tonumber(attrs.modification) or 0,
        scanned_at,
        scan_token,
        read_state.last_read_at,
        read_state.percent_finished,
        read_state.status,
        path)
end

function LibraryRepo:finishScan(root_path, scan_token, finished_at)
    local db = self.storage:open()
    local prefix = root_path
    if prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end
    db:exec("BEGIN IMMEDIATE;")
    local ok, err = pcall(function()
        local deactivate = db:prepare([[
            UPDATE books
            SET active=0
            WHERE active=1
              AND substr(path, 1, ?) = ?
              AND (scan_token IS NULL OR scan_token <> ?);
        ]])
        step_done(deactivate, #prefix, prefix, scan_token)
        local root_stmt = db:prepare([[
            UPDATE scan_roots SET last_scan_at=? WHERE path=?;
        ]])
        step_done(root_stmt, finished_at, root_path)
    end)
    if ok then
        db:exec("COMMIT;")
    else
        pcall(function() db:exec("ROLLBACK;") end)
        error(err)
    end
end

function LibraryRepo:getFingerprint(path)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT filesize, filemtime, metadata_version
        FROM books WHERE path = ? AND active = 1;
    ]])
    local row = stmt:reset():bind(path):step()
    if not row then return nil end
    return {
        filesize = tonumber(row[1]),
        filemtime = tonumber(row[2]),
        metadata_version = tonumber(row[3]) or 0,
    }
end

function LibraryRepo:getFingerprintMap(root_path)
    local db = self.storage:open()
    local prefix = root_path
    if prefix:sub(-1) ~= "/" then prefix = prefix .. "/" end
    local stmt = db:prepare([[
        SELECT path, filesize, filemtime, metadata_version
        FROM books
        WHERE active=1 AND substr(path, 1, ?) = ?;
    ]])
    stmt:reset():bind(#prefix, prefix)
    local map = {}
    while true do
        local row = stmt:step()
        if not row then break end
        map[row[1]] = {
            filesize = tonumber(row[2]),
            filemtime = tonumber(row[3]),
            metadata_version = tonumber(row[4]) or 0,
        }
    end
    return map
end

function LibraryRepo:adoptExistingRealMetadata(version)
    local db = self.storage:open()
    local stmt = db:prepare([[
        UPDATE books
        SET metadata_version=?
        WHERE metadata_version < ?
          AND (
              (series IS NOT NULL AND series <> '')
              OR (language IS NOT NULL AND language <> '')
              OR (description IS NOT NULL AND description <> '')
              OR EXISTS (
                  SELECT 1 FROM book_authors ba WHERE ba.book_id=books.id
              )
              OR EXISTS (
                  SELECT 1 FROM book_genres bg WHERE bg.book_id=books.id
              )
          );
    ]])
    step_done(stmt, version, version)
end

function LibraryRepo:countBooks()
    local db = self.storage:open()
    return tonumber(db:rowexec("SELECT count(*) FROM books WHERE active = 1;")) or 0
end

function LibraryRepo:listBooks(limit, offset)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT id, path, title, series, series_index, language, format,
               filesize, last_read_at, percent_finished, reading_status
        FROM books
        WHERE active = 1
        ORDER BY sort_title, title
        LIMIT ? OFFSET ?;
    ]])
    stmt:reset():bind(limit or 50, offset or 0)
    return collect_rows(stmt, function(row)
        return {
            id = tonumber(row[1]), path = row[2], title = row[3], series = row[4],
            series_index = tonumber(row[5]), language = row[6], format = row[7],
            filesize = tonumber(row[8]), last_read_at = tonumber(row[9]),
            percent_finished = tonumber(row[10]), reading_status = row[11],
        }
    end)
end


function LibraryRepo:countAuthors()
    local db = self.storage:open()
    return tonumber(db:rowexec([[
        SELECT count(DISTINCT a.id)
        FROM authors a
        JOIN book_authors ba ON ba.author_id=a.id
        JOIN books b ON b.id=ba.book_id
        WHERE b.active=1;
    ]])) or 0
end

function LibraryRepo:countSeries()
    local db = self.storage:open()
    return tonumber(db:rowexec([[
        SELECT count(DISTINCT series)
        FROM books
        WHERE active=1 AND series IS NOT NULL AND series<>'';
    ]])) or 0
end

function LibraryRepo:listAuthors()
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT a.id, a.name, count(DISTINCT b.id)
        FROM authors a
        JOIN book_authors ba ON ba.author_id=a.id
        JOIN books b ON b.id=ba.book_id
        WHERE b.active=1
        GROUP BY a.id, a.name
        ORDER BY a.sort_name, a.name;
    ]])
    return collect_rows(stmt, function(row)
        return { id=tonumber(row[1]), name=row[2], count=tonumber(row[3]) or 0 }
    end)
end

function LibraryRepo:listSeries()
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT series, count(*)
        FROM books
        WHERE active=1 AND series IS NOT NULL AND series<>''
        GROUP BY series
        ORDER BY lower(series), series;
    ]])
    return collect_rows(stmt, function(row)
        return { name=row[1], count=tonumber(row[2]) or 0 }
    end)
end

function LibraryRepo:listFolders()
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT directory, count(*)
        FROM books
        WHERE active=1
        GROUP BY directory
        ORDER BY lower(directory), directory;
    ]])
    return collect_rows(stmt, function(row)
        return { name=row[1], count=tonumber(row[2]) or 0 }
    end)
end

function LibraryRepo:listBooksByAuthor(author_id)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT
            b.id, b.path, b.title, b.series, b.series_index, b.language,
            b.format, b.filesize, b.last_read_at, b.percent_finished,
            b.reading_status, b.filemtime, b.added_at,
            COALESCE((
                SELECT group_concat(x.name, char(10))
                FROM (
                    SELECT a.name AS name
                    FROM book_authors ba2
                    JOIN authors a ON a.id=ba2.author_id
                    WHERE ba2.book_id=b.id
                    ORDER BY ba2.ordinal
                ) x
            ), '') AS authors,
            COALESCE((
                SELECT group_concat(y.name, char(10))
                FROM (
                    SELECT g.name AS name
                    FROM book_genres bg2
                    JOIN genres g ON g.id=bg2.genre_id
                    WHERE bg2.book_id=b.id
                    ORDER BY g.name
                ) y
            ), '') AS genres
        FROM books b
        JOIN book_authors ba ON ba.book_id=b.id
        WHERE b.active=1 AND ba.author_id=?
        ORDER BY CASE WHEN b.series IS NULL OR b.series='' THEN 1 ELSE 0 END,
                 lower(b.series), b.series_index, b.sort_title, b.title;
    ]])
    stmt:reset():bind(author_id)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
            filemtime=tonumber(row[12]), added_at=tonumber(row[13]),
            authors=row[14] or "", genres=row[15] or "",
        }
    end)
end

function LibraryRepo:listBooksBySeries(series)
    local db = self.storage:open()

    -- Keep this path intentionally simple. It is hit directly from a Menu
    -- callback on Kindle, so avoid nested aggregate subqueries here.
    local stmt = db:prepare([[
        SELECT
            id, path, title, series, series_index, language,
            format, filesize, last_read_at, percent_finished,
            reading_status, filemtime, added_at
        FROM books
        WHERE active=1 AND series=?
        ORDER BY CASE WHEN series_index IS NULL THEN 1 ELSE 0 END,
                 series_index, sort_title, title;
    ]])
    stmt:reset():bind(series)

    local books = collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
            filemtime=tonumber(row[12]), added_at=tonumber(row[13]),
            authors="", genres="",
        }
    end)

    local author_stmt = db:prepare([[
        SELECT a.name
        FROM book_authors ba
        JOIN authors a ON a.id=ba.author_id
        WHERE ba.book_id=?
        ORDER BY ba.ordinal, a.name;
    ]])
    local genre_stmt = db:prepare([[
        SELECT g.name
        FROM book_genres bg
        JOIN genres g ON g.id=bg.genre_id
        WHERE bg.book_id=?
        ORDER BY g.name;
    ]])

    for _, book in ipairs(books) do
        local authors = {}
        author_stmt:reset():bind(book.id)
        while true do
            local row = author_stmt:step()
            if not row then break end
            authors[#authors + 1] = row[1]
        end
        book.authors = table.concat(authors, "\n")

        local genres = {}
        genre_stmt:reset():bind(book.id)
        while true do
            local row = genre_stmt:step()
            if not row then break end
            genres[#genres + 1] = row[1]
        end
        book.genres = table.concat(genres, "\n")
    end

    return books
end

function LibraryRepo:listBooksByFolder(folder)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT
            b.id, b.path, b.title, b.series, b.series_index, b.language,
            b.format, b.filesize, b.last_read_at, b.percent_finished,
            b.reading_status, b.filemtime, b.added_at,
            COALESCE((
                SELECT group_concat(x.name, char(10))
                FROM (
                    SELECT a.name AS name
                    FROM book_authors ba2
                    JOIN authors a ON a.id=ba2.author_id
                    WHERE ba2.book_id=b.id
                    ORDER BY ba2.ordinal
                ) x
            ), '') AS authors,
            COALESCE((
                SELECT group_concat(y.name, char(10))
                FROM (
                    SELECT g.name AS name
                    FROM book_genres bg2
                    JOIN genres g ON g.id=bg2.genre_id
                    WHERE bg2.book_id=b.id
                    ORDER BY g.name
                ) y
            ), '') AS genres
        FROM books b
        WHERE b.active=1 AND b.directory=?
        ORDER BY b.sort_title, b.title;
    ]])
    stmt:reset():bind(folder)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
            filemtime=tonumber(row[12]), added_at=tonumber(row[13]),
            authors=row[14] or "", genres=row[15] or "",
        }
    end)
end

function LibraryRepo:listRecent(limit)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT
            b.id, b.path, b.title, b.series, b.series_index, b.language,
            b.format, b.filesize, b.last_read_at, b.percent_finished,
            b.reading_status, b.filemtime, b.added_at,
            COALESCE((
                SELECT group_concat(x.name, char(10))
                FROM (
                    SELECT a.name AS name
                    FROM book_authors ba2
                    JOIN authors a ON a.id=ba2.author_id
                    WHERE ba2.book_id=b.id
                    ORDER BY ba2.ordinal
                ) x
            ), '') AS authors,
            COALESCE((
                SELECT group_concat(y.name, char(10))
                FROM (
                    SELECT g.name AS name
                    FROM book_genres bg2
                    JOIN genres g ON g.id=bg2.genre_id
                    WHERE bg2.book_id=b.id
                    ORDER BY g.name
                ) y
            ), '') AS genres
        FROM books b
        WHERE b.active=1 AND b.last_read_at IS NOT NULL
        ORDER BY b.last_read_at DESC
        LIMIT ?;
    ]])
    stmt:reset():bind(limit or 100)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
            filemtime=tonumber(row[12]), added_at=tonumber(row[13]),
            authors=row[14] or "", genres=row[15] or "",
        }
    end)
end

function LibraryRepo:getMetadataVersion()
    local db = self.storage:open()
    return tonumber(db:rowexec(
        "SELECT value FROM meta WHERE key='metadata_version';")) or 0
end

function LibraryRepo:setMetadataVersion(version)
    local db = self.storage:open()
    local stmt = db:prepare([[
        INSERT INTO meta(key, value) VALUES ('metadata_version', ?)
        ON CONFLICT(key) DO UPDATE SET value=excluded.value;
    ]])
    step_done(stmt, tostring(version))
end

function LibraryRepo:getBookDetails(book_id)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT
            b.id, b.path, b.directory, b.title, b.series, b.series_index,
            b.language, b.description, b.format, b.filesize,
            b.last_read_at, b.percent_finished, b.reading_status,
            b.filemtime, b.added_at,
            COALESCE((
                SELECT group_concat(x.name, char(10))
                FROM (
                    SELECT a.name AS name
                    FROM book_authors ba
                    JOIN authors a ON a.id=ba.author_id
                    WHERE ba.book_id=b.id
                    ORDER BY ba.ordinal
                ) x
            ), '') AS authors,
            COALESCE((
                SELECT group_concat(y.name, char(10))
                FROM (
                    SELECT g.name AS name
                    FROM book_genres bg
                    JOIN genres g ON g.id=bg.genre_id
                    WHERE bg.book_id=b.id
                    ORDER BY g.name
                ) y
            ), '') AS genres
        FROM books b
        WHERE b.id=? AND b.active=1
        LIMIT 1;
    ]])
    stmt:reset():bind(book_id)
    local row = stmt:step()
    if not row then return nil end
    return {
        id=tonumber(row[1]), path=row[2], directory=row[3], title=row[4],
        series=row[5], series_index=tonumber(row[6]), language=row[7],
        description=row[8], format=row[9], filesize=tonumber(row[10]),
        last_read_at=tonumber(row[11]), percent_finished=tonumber(row[12]),
        reading_status=row[13], filemtime=tonumber(row[14]),
        added_at=tonumber(row[15]), authors=row[16] or "", genres=row[17] or "",
    }
end


function LibraryRepo:listCatalogBooks(limit, offset)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT
            b.id, b.path, b.title, b.series, b.series_index, b.language,
            b.format, b.filesize, b.last_read_at, b.percent_finished,
            b.reading_status, b.filemtime, b.added_at,
            COALESCE((
                SELECT group_concat(x.name, char(10))
                FROM (
                    SELECT a.name AS name
                    FROM book_authors ba2
                    JOIN authors a ON a.id=ba2.author_id
                    WHERE ba2.book_id=b.id
                    ORDER BY ba2.ordinal
                ) x
            ), '') AS authors,
            COALESCE((
                SELECT group_concat(y.name, char(10))
                FROM (
                    SELECT g.name AS name
                    FROM book_genres bg2
                    JOIN genres g ON g.id=bg2.genre_id
                    WHERE bg2.book_id=b.id
                    ORDER BY g.name
                ) y
            ), '') AS genres
        FROM books b
        WHERE b.active=1
        ORDER BY b.id
        LIMIT ? OFFSET ?;
    ]])
    stmt:reset():bind(limit or 10000, offset or 0)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
            filemtime=tonumber(row[12]), added_at=tonumber(row[13]),
            authors=row[14] or "", genres=row[15] or "",
        }
    end)
end


local FAVORITE_COLLECTIONS = {
    { slug="to_read", label="favorite_to_read", order=10 },
    { slug="read", label="favorite_read", order=20 },
    { slug="later", label="favorite_later", order=30 },
    { slug="worthy", label="favorite_worthy", order=40 },
    { slug="trash", label="favorite_trash", order=50 },
    { slug="unknown", label="favorite_unknown", order=60 },
}

local function favoriteCollectionName(slug)
    for _, spec in ipairs(FAVORITE_COLLECTIONS) do
        if spec.slug == slug then return "libraryx:favorite:" .. slug end
    end
end

function LibraryRepo:ensureFavoriteCollections()
    local db=self.storage:open()
    local stmt=db:prepare("INSERT OR IGNORE INTO collections(name,sort_order) VALUES (?,?);")
    for _,spec in ipairs(FAVORITE_COLLECTIONS) do
        step_done(stmt,"libraryx:favorite:"..spec.slug,spec.order)
    end
end

function LibraryRepo:listFavoriteCollections()
    self:ensureFavoriteCollections()
    local out={}
    for _,spec in ipairs(FAVORITE_COLLECTIONS) do
        out[#out+1]={slug=spec.slug,label=spec.label,order=spec.order}
    end
    return out
end

function LibraryRepo:hasFavorite(book_id,slug)
    local name=assert(favoriteCollectionName(slug),"unknown favorite tag")
    local db=self.storage:open()
    local stmt=db:prepare([[
        SELECT 1 FROM book_collections bc
        JOIN collections c ON c.id=bc.collection_id
        WHERE bc.book_id=? AND c.name=? LIMIT 1;
    ]])
    return stmt:reset():bind(book_id,name):step() ~= nil
end

function LibraryRepo:setFavorite(book_id,slug,enabled)
    local name=assert(favoriteCollectionName(slug),"unknown favorite tag")
    self:ensureFavoriteCollections()
    local db=self.storage:open()
    if enabled then
        local stmt=db:prepare("SELECT id FROM collections WHERE name=? LIMIT 1;")
        local row=stmt:reset():bind(name):step()
        assert(row and row[1],"favorite collection missing")
        step_done(db:prepare([[
            INSERT OR IGNORE INTO book_collections(book_id,collection_id) VALUES (?,?);
        ]]),book_id,row[1])
    else
        step_done(db:prepare([[
            DELETE FROM book_collections
            WHERE book_id=? AND collection_id=(SELECT id FROM collections WHERE name=? LIMIT 1);
        ]]),book_id,name)
    end
end


function LibraryRepo:listFavoriteBooks(slug)
    local name=slug and assert(favoriteCollectionName(slug),"unknown favorite tag") or nil
    self:ensureFavoriteCollections()
    local db=self.storage:open()
    local where=name and [[
        b.active=1 AND EXISTS (
            SELECT 1 FROM book_collections bc
            JOIN collections c ON c.id=bc.collection_id
            WHERE bc.book_id=b.id AND c.name=?
        )
    ]] or [[
        b.active=1 AND EXISTS (
            SELECT 1 FROM book_collections bc
            JOIN collections c ON c.id=bc.collection_id
            WHERE bc.book_id=b.id AND c.name LIKE 'libraryx:favorite:%'
        )
    ]]
    local stmt=db:prepare(([[SELECT
        b.id,b.path,b.title,b.series,b.series_index,b.language,
        b.format,b.filesize,b.last_read_at,b.percent_finished,
        b.reading_status,b.filemtime,b.added_at,
        COALESCE((SELECT group_concat(x.name,char(10)) FROM (
            SELECT a.name AS name FROM book_authors ba2
            JOIN authors a ON a.id=ba2.author_id
            WHERE ba2.book_id=b.id ORDER BY ba2.ordinal
        ) x),'') AS authors,
        COALESCE((SELECT group_concat(y.name,char(10)) FROM (
            SELECT g.name AS name FROM book_genres bg2
            JOIN genres g ON g.id=bg2.genre_id
            WHERE bg2.book_id=b.id ORDER BY g.name
        ) y),'') AS genres
        FROM books b WHERE ]]..where..[[
        ORDER BY b.sort_title,b.title,b.id;]]))
    if name then stmt:reset():bind(name) end
    return collect_rows(stmt,function(row)
        return {
            id=tonumber(row[1]),path=row[2],title=row[3],series=row[4],
            series_index=tonumber(row[5]),language=row[6],format=row[7],
            filesize=tonumber(row[8]),last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]),reading_status=row[11],
            filemtime=tonumber(row[12]),added_at=tonumber(row[13]),
            authors=row[14] or "",genres=row[15] or "",
        }
    end)
end

function LibraryRepo:deleteBookByPath(path)
    local db=self.storage:open()
    step_done(db:prepare("DELETE FROM books WHERE path=?;"),path)
end

return LibraryRepo
