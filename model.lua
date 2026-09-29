local Model = {}

local function trim(s)
    if not s then return nil end
    s = tostring(s):gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

function Model.normalizeSortText(s)
    s = trim(s)
    if not s then return "" end
    return s:lower()
end

function Model.splitMultiValue(value)
    if not value or value == "" then return {} end
    local out, seen = {}, {}
    for part in tostring(value):gmatch("[^\n]+") do
        part = trim(part)
        if part and not seen[part] then
            out[#out + 1] = part
            seen[part] = true
        end
    end
    return out
end

function Model.fileFormat(path)
    local ext = path and path:match("%.([^./]+)$")
    return ext and ext:upper() or ""
end

function Model.filename(path)
    return (path and path:match("([^/]+)$")) or path or ""
end

function Model.directory(path)
    return (path and path:match("^(.*)/[^/]+$")) or ""
end

function Model.bookRecord(path, attrs, props, read_state, now)
    props = props or {}
    attrs = attrs or {}
    read_state = read_state or {}
    local title = trim(props.title) or trim(props.display_title)
        or Model.filename(path):gsub("%.[^%.]+$", "")
    return {
        path = assert(path),
        directory = Model.directory(path),
        filename = Model.filename(path),
        filesize = tonumber(attrs.size) or 0,
        filemtime = tonumber(attrs.modification) or 0,
        scanned_at = assert(now),
        scan_token = read_state.scan_token,
        title = title,
        sort_title = Model.normalizeSortText(title),
        language = trim(props.language),
        series = trim(props.series),
        series_index = tonumber(props.series_index),
        description = trim(props.description),
        format = Model.fileFormat(path),
        active = 1,
        last_read_at = tonumber(read_state.last_read_at),
        percent_finished = tonumber(read_state.percent_finished),
        reading_status = trim(read_state.status) or "new",
        authors = Model.splitMultiValue(props.authors),
        genres = Model.splitMultiValue(props.keywords),
    }
end

return Model
