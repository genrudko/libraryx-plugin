package.path = "./?.lua;" .. package.path
local ScanPlan = require("scanplan")

assert(ScanPlan.sameFingerprint(
    { filesize = 123, filemtime = 456 },
    { size = 123, modification = 456 }))
assert(not ScanPlan.sameFingerprint(
    { filesize = 123, filemtime = 456 },
    { size = 124, modification = 456 }))
assert(not ScanPlan.sameFingerprint(nil, { size = 1, modification = 2 }))

local s = ScanPlan.newStats()
assert(s.visited == 0 and s.indexed == 0 and s.cancelled == false)
print("test_scanplan: PASS")
