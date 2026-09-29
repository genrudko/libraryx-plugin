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
                title, sort_title, language, series, series_index, description,
                format, active, last_read_at, percent_finished, reading_status
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                directory=excluded.directory,
                filename=excluded.filename,
                filesize=excluded.filesize,
                filemtime=excluded.filemtime,
                scanned_at=excluded.scanned_at,
                scan_token=excluded.scan_token,
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
            book.scanned_at, book.scan_token, book.title, book.sort_title, book.language,
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
    local stmt = db:prepare("SELECT filesize, filemtime FROM books WHERE path = ? AND active = 1;")
    local row = stmt:reset():bind(path):step()
    if not row then return nil end
    return { filesize = tonumber(row[1]), filemtime = tonumber(row[2]) }
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
        SELECT b.id, b.path, b.title, b.series, b.series_index, b.language,
               b.format, b.filesize, b.last_read_at, b.percent_finished,
               b.reading_status
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
        }
    end)
end

function LibraryRepo:listBooksBySeries(series)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT id, path, title, series, series_index, language, format,
               filesize, last_read_at, percent_finished, reading_status
        FROM books
        WHERE active=1 AND series=?
        ORDER BY series_index, sort_title, title;
    ]])
    stmt:reset():bind(series)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
        }
    end)
end

function LibraryRepo:listBooksByFolder(folder)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT id, path, title, series, series_index, language, format,
               filesize, last_read_at, percent_finished, reading_status
        FROM books
        WHERE active=1 AND directory=?
        ORDER BY sort_title, title;
    ]])
    stmt:reset():bind(folder)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
        }
    end)
end

function LibraryRepo:listRecent(limit)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT id, path, title, series, series_index, language, format,
               filesize, last_read_at, percent_finished, reading_status
        FROM books
        WHERE active=1 AND last_read_at IS NOT NULL
        ORDER BY last_read_at DESC
        LIMIT ?;
    ]])
    stmt:reset():bind(limit or 100)
    return collect_rows(stmt, function(row)
        return {
            id=tonumber(row[1]), path=row[2], title=row[3], series=row[4],
            series_index=tonumber(row[5]), language=row[6], format=row[7],
            filesize=tonumber(row[8]), last_read_at=tonumber(row[9]),
            percent_finished=tonumber(row[10]), reading_status=row[11],
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

function LibraryRepo:listCatalogBooks(limit, offset)
    local db = self.storage:open()
    local stmt = db:prepare([[
        SELECT
            b.id, b.path, b.title, b.series, b.series_index, b.language,
            b.format, b.filesize, b.last_read_at, b.percent_finished,
            b.reading_status,
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
            authors=row[12] or "", genres=row[13] or "",
        }
    end)
end

return LibraryRepo
