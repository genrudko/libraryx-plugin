local ScanPlan = {}

function ScanPlan.sameFingerprint(existing, attrs)
    if not existing or not attrs then return false end
    return tonumber(existing.filesize) == tonumber(attrs.size)
        and tonumber(existing.filemtime) == tonumber(attrs.modification)
end

function ScanPlan.newStats()
    return {
        visited = 0,
        indexed = 0,
        unchanged = 0,
        unsupported = 0,
        missing = 0,
        errors = 0,
        cancelled = false,
    }
end

return ScanPlan
