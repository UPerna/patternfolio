-- One fresh-runtime workload. Timed calls contain actual shared generation,
-- validation, planning and vector serialization. Measurements are not semantic.
local clock=_bench_wall or os.clock;local started=clock()
local P,Q,C,H,V=require('pattern'),require('pattern_recipe'),require('pattern_cli_core'),require('pattern_hash'),require('pattern_render')
local fs=require('lfs');local Parse=require('pattern_parse')
local function read(p)local f=assert(io.open(p,'rb'));local b=f:read('*a');f:close();return b end
local id=assert(arg[1],'workload id required');local label=arg[2]or 'measurement'
assert(label:match('^[%w_-]+$'),'measurement label')
local manifest=Parse.decode(read('build/performance/workloads.json'));assert(manifest.status=='passed')
local row;for _,r in ipairs(manifest.cases)do if r.id==id then row=r;break end end;assert(row,'unknown prepared workload')
local raw=read('build/performance/'..row.recipe_path);assert(H.sha256(raw)==row.recipe_sha256,'workload bytes changed')
local q=Q.decode(raw);local reg,definition=C.registry(q.definition.id);local source={}
for name in fs.dir('.')do if name:match('%.lua$')then source[name]=read(name)end end
for _,name in ipairs{'tools/perf_run.lua','tools/perf_workloads.lua','tools/perf_prepare.lua'}do source[name]=read(name)end
local env=Q.environment({revision='working/performance34',files={construction=source,style={},view={},renderer={}}},
 {lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/performance34'},{id=V.VERSION,version='1'})
local bootstrap=clock()-started;local original;local phases=P.array();local failed
local function counts(x)
 local a={};for name,structure in pairs(x.structures)do
  local n={};for key,value in pairs(structure)do if type(value)=='table'and #value>0 then n[key]=#value end end;a[name]=n
 end
 if x.extensions and x.extensions.legacy then a.legacy={drawing_operations=x.extensions.legacy.capture.count,chunks=#x.extensions.legacy.chunks}end
 if x.extensions and x.extensions.freeform then local n=0;for _ in pairs(x.extensions.freeform.packing.circles)do n=n+1 end;a.circle_packing={circles=n,triangles=#x.extensions.freeform.packing.complex.faces}end
 if x.extensions and x.extensions.micrography then a.micrography={graphemes=#x.extensions.micrography.clusters,streamlines=#x.extensions.micrography.streamlines}end
 return a
end
for _,mode in ipairs{'cold-generation','warm-generation','validated-instance-replay'}do
 collectgarbage('collect');local before=collectgarbage('count')*1024;local start=clock()
 local saved=reg.generate;if mode=='validated-instance-replay'then reg.generate=function()error('Benchmark replay invoked generator')end end
 local ok,value=pcall(function()return mode=='validated-instance-replay'and Q.replay(q,original.instance,original.record,reg,env)or Q.execute(q,reg,env)end)
 reg.generate=saved;local generated=clock()
 if not ok or value.record.status~='complete'then
  failed={phase=mode,status=ok and value.record.status or 'failed',diagnostics=ok and P.plain(value.record.diagnostics)or {tostring(value)},accepted_outputs=ok and #value.record.outputs or 0,elapsed_seconds=generated-start};break
 end
 local result=value;local plan=V.plan(result.scene,result.instance,result.view,definition);local pdf,svg=V.pdf(plan),V.svg(plan);local finished=clock()
 if original then assert(result.bytes.instance==original.bytes.instance and result.bytes.scene==original.bytes.scene,'Semantic cold/warm/replay drift')else original=result end
 local after=collectgarbage('count')*1024;collectgarbage('collect');local retained=collectgarbage('count')*1024
 phases[#phases+1]={phase=mode,generation_validation_hash_seconds=generated-start,vector_serialization_seconds=finished-generated,total_seconds=finished-start,
  lua_bytes_before=math.floor(before),lua_bytes_after_before_collection=math.floor(after),lua_bytes_after_full_collection=math.floor(retained),
  instance_bytes=#result.bytes.instance,scene_bytes=#result.bytes.scene,pdf_bytes=#pdf,svg_bytes=#svg,
  instance_sha256=result.record.outputs[1].sha256,scene_sha256=result.record.outputs[2].sha256,object_counts=counts(result.instance),
  budgets=P.plain(result.record.budgets),solver=result.record.extensions and result.record.extensions.solver or nil,
  byte_hash_cache=H.sha256_cache_stats and H.sha256_cache_stats()or nil}
 print('Measured actual workload',id,mode,string.format('%.6f',finished-start))
end
local receipt={schema_version=1,status=failed and 'failed'or 'passed',workload=row,source_digest=env.source.digest,source_files_sha256=P.plain(env.source.files.construction),actual_lua=_VERSION,
 host=PATTERN_TEST_HOST or 'texlua/performance34',measurement_clock=_bench_wall and 'Python time.perf_counter wall seconds'or 'os.clock CPU estimate; platform semantics apply',
 bootstrap_loading_source_verification_seconds=bootstrap,phases=phases,failure=failed,semantic_cold_warm_replay_equal=not failed,
 scope='One fresh runtime, no instruction profiling hooks. Lua memory snapshots distinguish transient allocations and full collection; these are not whole-process memory or exact per-phase peaks. Measurements stay outside recipe/instance/scene hashes.'}
for _,p in ipairs{'build','build/performance','build/performance/results'}do fs.mkdir(p)end
local path='build/performance/results/'..id..'-'..label..'-'.._VERSION:gsub(' ','-')..'.json';local f=assert(io.open(path,'wb'));f:write(P.serialize(receipt));f:close()
assert(not failed,failed and P.serialize(failed)or 'benchmark failed');return receipt
