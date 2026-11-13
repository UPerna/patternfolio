local P,Q,H=require('pattern'),require('pattern_recipe'),require('pattern_hash')
local C=require('pattern_cli_core');local fs=require('lfs');local W=dofile('tools/perf_workloads.lua')
for _,p in ipairs{'build','build/performance','build/performance/recipes'}do fs.mkdir(p)end
local rows=P.array();local failures=P.array()
for _,descriptor in ipairs(W.catalog())do
 local ok,value=pcall(function()
  local q=W.recipe(descriptor.id);local reg=C.registry(q.definition.id);reg:check_specification(q.definition.id,q.design)
  local bytes=Q.encode(q);assert(#bytes<=2*1024*1024,'Prepared recipe exceeds public transport')
  local path='recipes/'..descriptor.id..'.recipe';local f=assert(io.open('build/performance/'..path,'wb'));f:write(bytes);f:close()
  local row=P.plain(descriptor);row.recipe_path=path;row.recipe_sha256=H.sha256(bytes);row.recipe_bytes=#bytes;row.seed=q.design.seed;row.definition={id=q.definition.id,version=q.definition.version};return row
 end)
 if ok then rows[#rows+1]=value else failures[#failures+1]={id=descriptor.id,error=tostring(value)}end
end
local source={};for _,name in ipairs{'tools/perf_workloads.lua','tools/perf_prepare.lua'}do local f=assert(io.open(name,'rb'));source[name]=H.sha256(f:read('*a'));f:close()end
local result={schema_version=1,version=W.VERSION,status=#failures==0 and 'passed'or 'failed',cases=rows,failures=failures,source_files=source,scope='Canonical recipes prepared through actual definition/specification/document/planner APIs; generation, timings and structural validation remain separate checks.'}
local f=assert(io.open('build/performance/workloads.json','wb'));f:write(P.serialize(result));f:close();print('Prepared actual performance recipes',#rows,'failures',#failures)
assert(#failures==0,P.serialize(failures));return result
