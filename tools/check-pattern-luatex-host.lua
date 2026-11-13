-- Exercise the actual host's fallback lookup from a separate build directory.
local lfs,H,P=require('lfs'),require('pattern_hash'),require('pattern')
local root=lfs.currentdir():gsub('\\','/')
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local script=read('tools/check-pattern-luatex-host.lua')
local recipe=read('examples/patterns/hybrid.recipe')
local original_kpse=kpse;local original_path=package.path
package.path=root..'/?.lua;'..package.path
kpse={find_file=function(name)
  if name=='hybrid.recipe'then return root..'/examples/patterns/hybrid.recipe'end
  return root..'/'..name
end}
if not status then status={luatex_version=0,luatex_revision='standalone-file-lookup-test'}end
lfs.mkdir('build');lfs.mkdir('build/pattern-luatex-host')
local sources={}
for name in lfs.dir(root)do
  if name:match('%.lua$') or name:match('^florilegium.*%.sty$') or name:match('^florilegium.*%.def$')then
    sources[name]=H.sha256(read(root..'/'..name))
  end
end
local directory='build/pattern-luatex-host/'..H.value('host/lookup-test',{script=H.sha256(script),recipe=H.sha256(recipe),
  lua=_VERSION,host_version=tostring(status.luatex_version),host_revision=tostring(status.luatex_revision),sources=sources})
lfs.mkdir(directory);assert(lfs.chdir(directory))
assert(not io.open('hybrid.recipe','rb'),'Regression must exercise fallback rather than a direct file')
require('pattern_luatex').declare('fallback','hybrid.recipe')
local records=0
for name in lfs.dir('.')do
  if name:match('%.record$')then
    local record=P.build_record(require('pattern_parse').decode(read(name)))
    assert(record.status=='complete');records=records+1
  end
end
assert(records==1,'Fallback declaration failed to persist its validated generation')
local receipt={schema_version=1,scope='Standalone regression of actual LuaLaTeX host file lookup and declaration',
  script_sha256=H.sha256(script),recipe_sha256=H.sha256(recipe),lua=_VERSION,source_files=sources,complete_generation_records=records,
  fallback_lookup=true,tex_document_integration='Verified separately by the real native book consumer'}
local f=assert(io.open('receipt.json','wb'));f:write(P.serialize(receipt));f:close()
assert(lfs.chdir(root));kpse=original_kpse;package.path=original_path
print('LuaLaTeX host fallback lookup/declaration regression passed')
