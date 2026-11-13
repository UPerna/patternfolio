-- Exercise the real external record adapter without claiming a TeX compile.
local P,H,X=require('pattern'),require('pattern_hash'),require('pattern_xetex')
local lfs=require('lfs');local root=lfs.currentdir():gsub('\\','/');local checks=0
local original_path=package.path;package.path=root..'/?.lua;'..package.path
local function check(ok,why)assert(ok,why);checks=checks+1 end
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local function reject(fn,phrase)
  local ok,error=pcall(fn);check(not ok and tostring(error):find(phrase,1,true),'missing failure: '..phrase..' / '..tostring(error))
end
local script=read('tools/check-pattern-xetex.lua')
local source={}
for name in lfs.dir(root)do if name:match('%.lua$') or name:match('^florilegium.*%.sty$') or name:match('^florilegium.*%.def$')then source[name]=H.sha256(read(root..'/'..name))end end
local inputs={['examples/cli/periodic.recipe']=H.sha256(read('examples/cli/periodic.recipe'))}
local identity=H.value('external/check',{source=source,inputs=inputs,script=H.sha256(script),lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua'})
lfs.mkdir('build');lfs.mkdir('build/pattern-xetex');local folder='build/pattern-xetex/'..identity;lfs.mkdir(folder);assert(lfs.chdir(folder))
local records,env=X.records()
env.PHEADER{schema_version=1,adapter='pattern-tex-v1',engine='XeTeX',version=0,revision='standalone-record-test'}
env.PDECLARE{name='p',path=root..'/examples/cli/periodic.recipe'}
env.PDECLARE{name='alias',path=root..'/examples/cli/periodic.recipe'}
env.PINLINE{id=1,name='p',width=0}
local CM=2.54/(72.27*65536);local function sp(cm)return math.floor(cm/CM+.5)end
env.PPAGE{n=1,page=42,label='xlii',twoside=false,paperwidth=sp(10),paperheight=sp(12),hoffset=sp(.3),voffset=sp(-.2),
  oddsidemargin=sp(2-2.54-.3),evensidemargin=sp(2-2.54-.3),textwidth=sp(6),topmargin=sp(-.84),
  headheight=sp(.2),headsep=sp(.3),textheight=sp(8),footskip=sp(.5)}
env.PMARK{n=1,kind='heading',arg=0,x=sp(2),y=sp(9)}
env.PMARK{n=1,kind='pattern_inline',arg={id=1,name='p'},x=sp(4),y=sp(5)}
env.PMARK{n=1,kind='pattern_view',arg={name='p',region='outer',spread='none',protect='true',padding=sp(.1)},x=0,y=0}
env.PEND{active=true,pending=false,inline_count=1,shipped=1}
local evidence=X.render('source',records,root)
local trace=require('pattern_parse').decode(read('source-patterns.json'))
check(evidence.active and trace.protocol==X.VERSION,'external protocol was not retained')
check(trace.unique_generations==1 and #trace.declarations==2,'declaration aliases regenerated semantic construction')
check(trace.declarations[1].instance_sha256==trace.declarations[2].instance_sha256,'alias changed semantic instance')
check(trace.actual_shipped_pages==1 and trace.pages[1].geometry.index==1 and trace.pages[1].geometry.logical_number==42,'actual physical index was confused with logical label')
check(math.abs(trace.pages[1].geometry.content[1]-2)<1e-5 and math.abs(trace.pages[1].geometry.content[4]-10)<1e-5,'custom offsets changed physical content geometry')
check(trace.pages[1].geometry.markers[1].kind=='heading' and trace.pages[1].geometry.markers[1].arg==0,'heading marker was lost')
check(#trace.pages[1].geometry.inline_positions==1 and trace.inline[1].print_requirements.status=='passed','inline placement/print evidence missing')
check(trace.physical_views==1 and #trace.pages[1].outputs==1,'page view missing')
check(read('source-patterns.tex'):find('flo@ppage@1',1,true) and read('source-patterns.tex'):find('flo@pinline@1',1,true),'external inclusion metadata missing')
local outputs={}
for path,digest in pairs(evidence.outputs)do check(H.sha256(read(path))==digest,'output hash mismatch: '..path);outputs[path]=digest end
for path,digest in pairs(evidence.dependencies)do check(H.sha256(read(path))==digest,'dependency hash mismatch: '..path)end
local bad,badenv=X.records();badenv.PHEADER{schema_version=99,adapter='pattern-tex-v1',engine='XeTeX'}
reject(function()X.render('bad',bad,root)end,'unsupported or missing')
bad,badenv=X.records();badenv.PHEADER{schema_version=1,adapter='pattern-tex-v1',engine='XeTeX'}
reject(function()X.render('bad',bad,root)end,'incomplete external')
bad,badenv=X.records();badenv.PHEADER{schema_version=1,adapter='pattern-tex-v1',engine='XeTeX'}
badenv.PMARK{n=2,kind='heading',arg=0,x=0,y=0};badenv.PEND{active=true,pending=false,inline_count=0,shipped=1}
reject(function()X.render('bad',bad,root)end,'mark has no actual shipped page')
local occupied=trace.inline[1].prefix..'.pdf';local original=read(occupied)
local f=assert(io.open(occupied,'wb'));f:write('Occupied test file\n');f:close()
reject(function()X.render('collision',records,root)end,'existing generated filename has different bytes')
check(read(occupied)=='Occupied test file\n','external adapter replaced an occupied file')
f=assert(io.open(occupied,'wb'));f:write(original);f:close()
-- Exercise replacement on Windows as well as POSIX, including rollback.
local rename=os.rename;local target='replace.tex'
os.rename=function(a,b)
  local old=io.open(b,'rb');if old then old:close();return nil,'simulated Windows target exists'end
  return rename(a,b)
end
X.replace(target,'first');X.replace(target,'second');X.replace(target,'second')
check(read(target)=='second' and read(target..'.previous-'..H.sha256('first'))=='first','previous metadata was not preserved on replacement')
os.rename=function(a,b)if a==target..'.tmp'then return nil,'simulated publish failure'end;return rename(a,b)end
reject(function()X.replace(target,'third')end,'cannot publish generated metadata')
check(read(target)=='second','failed metadata publication did not restore old bytes');os.rename=rename
local receipt={schema_version=1,source_digest=identity,source_files=source,input_files=inputs,script_sha256=H.sha256(script),checks=checks,
  outputs=outputs,lua=_VERSION,scope='Actual external record adapter, shared generators and file publication; native TeX integration is a separate required gate',
  native_tex_compiled=false,semantic_generations=1,physical_views=1,occupied_file_preserved=true,metadata_rollback_checked=true}
f=assert(io.open('receipt.json','wb'));f:write(P.serialize(receipt));f:close();assert(lfs.chdir(root));package.path=original_path
print('External record adapter checks',checks,identity)
