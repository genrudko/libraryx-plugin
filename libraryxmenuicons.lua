local M = {}

-- Private-use glyphs from KOReader's bundled symbols fallback font.
-- Keep them outside translated strings so localization files stay clean.
M.BOOK       = "\xEF\x80\xAD" -- book
M.USERS      = "\xEF\x83\x80" -- users
M.SERIES     = "\xEF\x80\xAE" -- bookmark
M.TITLES     = "\xEF\x80\xBA" -- list
M.FOLDER     = "\xEF\x81\xBC" -- folder-open
M.RANDOM     = "\xEF\x81\xB4" -- random
M.FILTER     = "\xEF\x82\xB0" -- filter
M.SETTINGS   = "\xEF\x80\x93" -- cog
M.REFRESH    = "\xEF\x80\xA1" -- refresh
M.STAR       = "\xEF\x80\x85" -- star
M.LIBRARY    = M.BOOK
M.LIST       = M.TITLES
M.PREVIEW    = "\xEF\x81\xAE" -- eye
M.NAVIGATION = "\xEF\x84\xA4" -- location arrow
M.DATABASE   = "\xEF\x87\x80" -- database
M.UPDATES    = M.REFRESH
M.LANGUAGE   = "\xEF\x86\xAB" -- language
M.INFO       = "\xEF\x81\x9A" -- info-circle
M.DOWNLOAD   = "\xEF\x80\x99" -- download
M.RESET      = "\xEF\x83\xA2" -- undo

function M.label(glyph, text)
    if type(glyph) ~= "string" or glyph == "" then return text end
    return glyph .. "  " .. tostring(text or "")
end

return M
