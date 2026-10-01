package.path = './?.lua;' .. package.path

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function commandOK(cmd)
    local ok = os.execute(cmd)
    return ok == true or ok == 0
end

local function pathMode(path)
    if commandOK("test -d " .. shellQuote(path)) then return "directory" end
    local f = io.open(path, "rb")
    if f then f:close(); return "file" end
end

local fake_lfs = {}
function fake_lfs.attributes(path, field)
    local mode = pathMode(path)
    if field == "mode" then return mode end
    return mode and { mode = mode } or nil
end
function fake_lfs.mkdir(path)
    return commandOK("mkdir -p " .. shellQuote(path))
end

local fake_ffi_util = {}
function fake_ffi_util.purgeDir(path)
    local ok = commandOK("rm -rf " .. shellQuote(path))
    return ok, ok and nil or "rm failed"
end

local archive_version = "0.4.5-beta"
local Reader = {}
Reader.__index = Reader
function Reader:new() return setmetatable({}, self) end
function Reader:open()
    self.entries = {
        { path = "libraryx.koplugin/_meta.lua",
          content = "return { name='libraryx', version='" .. archive_version .. "' }\n" },
        { path = "libraryx.koplugin/new.lua", content = "return true\n" },
    }
    return true
end
function Reader:iterate()
    local i = 0
    return function()
        i = i + 1
        return self.entries[i]
    end
end
function Reader:extractToPath(source, dest)
    local found
    for _, entry in ipairs(self.entries or {}) do
        if entry.path == source then found = entry; break end
    end
    if not found then self.err = "entry missing"; return false end
    local parent = dest:match("^(.*)/[^/]+$")
    if parent then os.execute("mkdir -p " .. shellQuote(parent)) end
    local f = io.open(dest, "wb")
    if not f then self.err = "write failed"; return false end
    f:write(found.content or "")
    f:close()
    return true
end
function Reader:close() end

package.loaded['ui/widget/confirmbox'] = { new=function(_,x) return x end }
package.loaded['ui/widget/infomessage'] = { new=function(_,x) return x end }
package.loaded['ui/widget/textviewer'] = { new=function(_,x) return x end }
package.loaded['ui/uimanager'] = { show=function() end, scheduleIn=function(_,_,cb) if cb then cb() end end }
package.loaded['device'] = { canOpenLink=function() return false end }
package.loaded['libraryxsettings'] = {
    updateChannel=function() return 'beta' end,
    autoUpdateCheck=function() return true end,
}
package.loaded['libs/libkoreader-lfs'] = fake_lfs
package.loaded['ffi/util'] = fake_ffi_util
package.loaded['ffi/archiver'] = { Reader = Reader }

local U=require('libraryxupdater')

local f_updater = assert(io.open('libraryxupdater.lua', 'r'))
local updater_source = f_updater:read('*a')
f_updater:close()
assert(updater_source:find('local new_version = tostring(release.tag_name or ""):gsub("^v", "")', 1, true),
    'Updater.install must derive the expected version from the selected release')
assert(updater_source:find('installStaged(zip_path, pluginDir(), new_version)', 1, true),
    'Updater.install must pass the selected release version to staged validation')

assert(U._isNewer('0.4.0-beta','0.3.0-beta'))
assert(U._isNewer('0.4.0','0.4.0-beta'))
assert(not U._isNewer('0.4.0-beta','0.4.0'))
assert(not U._isNewer('0.3.9','0.4.0-beta'))

local releases={
 {tag_name='v0.5.0-beta', prerelease=true, draft=false, assets={}},
 {tag_name='v0.4.1', prerelease=false, draft=false, assets={}},
}
assert(U._selectRelease(releases,'beta').tag_name=='v0.5.0-beta')
assert(U._selectRelease(releases,'stable').tag_name=='v0.4.1')

assert(U._safeRelativePath("main.lua") == "main.lua")
assert(U._safeRelativePath("docs/README.md") == "docs/README.md")
assert(U._safeRelativePath("../escape.lua") == nil)
assert(U._safeRelativePath("docs/../escape.lua") == nil)
assert(U._safeRelativePath("/absolute.lua") == nil)
assert(U._safeRelativePath("docs\\escape.lua") == nil)

local tmp = "/tmp/libraryx-updater-runtime-test"
fake_ffi_util.purgeDir(tmp)
assert(fake_lfs.mkdir(tmp))
local final_dir = tmp .. "/libraryx.koplugin"

local function writeOld()
    fake_ffi_util.purgeDir(final_dir)
    assert(fake_lfs.mkdir(final_dir))
    local f = assert(io.open(final_dir .. "/old.lua", "wb"))
    f:write("return 'old'\n")
    f:close()
end

-- Successful install replaces the complete directory, so removed old files
-- cannot linger after an update.
writeOld()
local ok, err = U._installStaged("fake.zip", final_dir, "0.4.5-beta")
assert(ok, tostring(err))
assert(pathMode(final_dir .. "/new.lua") == "file")
assert(pathMode(final_dir .. "/old.lua") == nil)
assert(pathMode(final_dir .. ".libraryx-update") == nil)
assert(pathMode(final_dir .. ".libraryx-backup") == nil)

-- A mismatched release asset is rejected before the live plugin is renamed.
writeOld()
archive_version = "9.9.9-beta"
ok, err = U._installStaged("fake.zip", final_dir, "0.4.5-beta")
assert(not ok and tostring(err):find("version mismatch", 1, true))
assert(pathMode(final_dir .. "/old.lua") == "file")
assert(pathMode(final_dir .. ".libraryx-backup") == nil)
archive_version = "0.4.5-beta"

-- If activation of the staged directory fails after the backup rename, the
-- previous plugin directory is restored.
writeOld()
local real_rename = os.rename
os.rename = function(src, dst)
    if src == final_dir .. ".libraryx-update" then
        return nil, "forced activation failure"
    end
    return real_rename(src, dst)
end
ok, err = U._installStaged("fake.zip", final_dir, "0.4.5-beta")
os.rename = real_rename
assert(not ok and tostring(err):find("forced activation failure", 1, true))
assert(pathMode(final_dir .. "/old.lua") == "file")
assert(pathMode(final_dir .. ".libraryx-backup") == nil)

fake_ffi_util.purgeDir(tmp)
print('test_updater_runtime: PASS')
