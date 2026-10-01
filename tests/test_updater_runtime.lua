package.path = './?.lua;' .. package.path
package.loaded['ui/widget/confirmbox'] = { new=function(_,x) return x end }
package.loaded['ui/widget/infomessage'] = { new=function(_,x) return x end }
package.loaded['ui/widget/textviewer'] = { new=function(_,x) return x end }
package.loaded['ui/uimanager'] = { show=function() end, scheduleIn=function(_,_,cb) if cb then cb() end end }
package.loaded['device'] = { canOpenLink=function() return false end }
package.loaded['libraryxsettings'] = {
    updateChannel=function() return 'beta' end,
    autoUpdateCheck=function() return true end,
}
local U=require('libraryxupdater')
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
print('test_updater_runtime: PASS')
