-- Failure evidence from the real public pipeline, not a mock generator.
local P,Q,C,H,V=require('pattern'),require('pattern_recipe'),require('pattern_cli_core'),require('pattern_hash'),require('pattern_render')
local fs,Parse=require('lfs'),require('pattern_parse')
local function read(p)local f=assert(io.open(p,'rb'));local b=f:read('*a');f:close();return b end
local source={};for n in fs.dir('.')do if n:match('%.lua$')then source[n]=read(n)end end
source['tools/check-performance-bounds.lua']=read('tools/check-performance-bounds.lua')
local env=Q.environment({revision='working/performance34-bounds',files={construction=source,style={},view={},renderer={}}},{lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/performance34'},{id=V.VERSION,version='1'})
local manifest=Parse.decode(read('build/performance/workloads.json'));local rows=P.array();local checks=0
fs.mkdir('build');fs.mkdir('build/performance-bounds')
local function save(status,failure)
 local value={status=status,checks=checks,actual_lua=_VERSION,source_digest=env.source.digest,source_files_sha256=P.plain(env.source.files.construction),cases=rows,failure=failure}
 local f=assert(io.open('build/performance-bounds/receipt-'.._VERSION:gsub(' ','-')..'.json','wb'));f:write(P.serialize(value));f:close();return value
end
local function check(ok,why)if not ok then save('failed',why);error(why,0)end end
for _,row in ipairs(manifest.cases)do if row.size=='small'then
 local raw=read('build/performance/'..row.recipe_path);assert(H.sha256(raw)==row.recipe_sha256)
 local q=Q.decode(raw);local reg=C.registry(q.definition.id)
 for _,threshold in ipairs{1,2,4}do
  local calls=0;local r=Q.execute(q,reg,env,{cancelled=function()calls=calls+1;return calls>=threshold end})
  check(calls==threshold and r.record.status=='cancelled'and #r.record.outputs==0,'Cancellation was accepted as a complete patch:'..row.id..'/'..threshold)
  rows[#rows+1]={id=row.id,kind='cancellation',checkpoint=threshold,calls=calls,status=r.record.status,accepted_outputs=#r.record.outputs,diagnostics=P.plain(r.record.diagnostics)};checks=checks+1
 end
 for _,name in ipairs{'objects','operations','bytes'}do
  local limits={objects=100000,operations=48000000,bytes=67108864};limits[name]=0
  local r=Q.execute(q,reg,env,{limits=limits})
  check(r.record.status=='failed'and #r.record.outputs==0,'Exhaustion was accepted as a complete patch:'..row.id..'/'..name)
  check(P.serialize(r.record.diagnostics):find('budget exhausted',1,true),'Unexpected resource failure:'..row.id..'/'..name)
  rows[#rows+1]={id=row.id,kind='budget_exhaustion',resource=name,status=r.record.status,accepted_outputs=#r.record.outputs,diagnostics=P.plain(r.record.diagnostics)};checks=checks+1
 end
 save('in_progress')
end end
assert(checks==54,'Required family/bound coverage missing')
local receipt=save('passed');print('Actual performance cancellation/exhaustion checks',checks,_VERSION);return receipt
