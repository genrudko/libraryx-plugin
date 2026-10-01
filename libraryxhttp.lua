local M = {}

local function shellQuote(value)
    local s = tostring(value or ""):gsub("'", "'\\''")
    return "'" .. s .. "'"
end

function M.getJSON(url, user_agent)
    local JSON = require("json")
    local ok_require, http, ltn12, socket, socketutil = pcall(function()
        return require("socket.http"), require("ltn12"),
               require("socket"), require("socketutil")
    end)
    if ok_require then
        local body = {}
        local ok_req, code = pcall(function()
            socketutil:set_timeout(
                socketutil.LARGE_BLOCK_TIMEOUT,
                socketutil.LARGE_TOTAL_TIMEOUT)
            local c = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = {
                    ["User-Agent"] = user_agent or "KOReader-LibraryX",
                    ["Accept"] = "application/vnd.github+json",
                },
                sink = ltn12.sink.table(body),
                redirect = true,
            }))
            socketutil:reset_timeout()
            return c
        end)
        pcall(function() socketutil:reset_timeout() end)
        if ok_req and tonumber(code) == 200 then
            local ok, data = pcall(JSON.decode, table.concat(body))
            if ok then return data end
        end
    end

    local handle = io.popen(string.format(
        "curl -sfL --connect-timeout 5 --max-time 20 -H %s -H %s %s",
        shellQuote("User-Agent: " .. (user_agent or "KOReader-LibraryX")),
        shellQuote("Accept: application/vnd.github+json"),
        shellQuote(url)))
    if handle then
        local body = handle:read("*a")
        local ok_close = handle:close()
        if ok_close and body and body ~= "" then
            local ok, data = pcall(JSON.decode, body)
            if ok then return data end
        end
    end
    return nil
end

function M.download(url, path, user_agent)
    local ok_require, http, ltn12, socket, socketutil = pcall(function()
        return require("socket.http"), require("ltn12"),
               require("socket"), require("socketutil")
    end)
    if ok_require then
        local tmp = path .. ".tmp"
        pcall(os.remove, tmp)
        local file = io.open(tmp, "wb")
        if file then
            local ok_req, code = pcall(function()
                socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, 300)
                local sink = socketutil.file_sink and socketutil.file_sink(file)
                    or ltn12.sink.file(file)
                local c = socket.skip(1, http.request({
                    url = url,
                    method = "GET",
                    headers = {
                        ["User-Agent"] = user_agent or "KOReader-LibraryX",
                        ["Accept"] = "application/zip, application/octet-stream, */*",
                    },
                    sink = sink,
                    redirect = true,
                }))
                socketutil:reset_timeout()
                return c
            end)
            pcall(function() file:close() end)
            pcall(function() socketutil:reset_timeout() end)
            if ok_req and tonumber(code) == 200 then
                pcall(os.remove, path)
                if os.rename(tmp, path) then return true end
            end
            pcall(os.remove, tmp)
        end
    end

    pcall(os.remove, path)
    local ret = os.execute(string.format(
        "curl -sfL --connect-timeout 10 --max-time 300 -o %s %s",
        shellQuote(path), shellQuote(url)))
    return ret == 0 or ret == true
end

return M
