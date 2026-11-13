-- Operational measurements are outside semantic recipe/build hashes.
local clock=_bench_wall or os.clock
local first=clock()
local samples,instructions,peak={},0,0
local profile=arg and arg[2]=='profile'
local function hook()
 instructions=instructions+100000
 local info=debug.getinfo(2,'Sl');local name=info and info.short_src or 'unknown'
 samples[name]=(samples[name]or 0)+1;peak=math.max(peak,collectgarbage('count')*1024)
end
if profile then debug.sethook(hook,'',100000)end
local P,Q,C,H,V=require('pattern'),require('pattern_recipe'),require('pattern_cli_core'),require('pattern_hash'),require('pattern_render')
local fs=require('lfs');local source={};local function read(p)local f=assert(io.open(p,'rb'));local b=f:read('*a');f:close();return b end
for name in fs.dir('.')do if name:match('%.lua$')then source[name]=read(name)end end
source['tools/perf_probe.lua']=read('tools/perf_probe.lua')
local family=arg and arg[1]or 'periodic';local q=Q.decode(read('examples/cli/'..family..'.recipe'))
local registry,definition=C.registry(q.definition.id)
local env=Q.environment({revision='working/performance34',files={construction=source,style={},view={},renderer={}}},{lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/performance34'},{id=V.VERSION,version='1'})
local initialized=clock();local phases=P.array();local original
for i,mode in ipairs{'cold-generation','warm-generation','validated-instance-replay'}do
 collectgarbage('collect');local before=collectgarbage('count')*1024;local t=clock()
 local result=mode=='validated-instance-replay'and Q.replay(q,original.instance,original.record,registry,env)or Q.execute(q,registry,env)
 local generated=clock();assert(result.record.status=='complete',P.serialize(result.record.diagnostics))
 local plan=V.plan(result.scene,result.instance,result.view,definition);local pdf,svg=V.pdf(plan),V.svg(plan);local finished=clock()
 if original then assert(result.bytes.instance==original.bytes.instance and result.bytes.scene==original.bytes.scene,'Cold/warm/replay semantic drift')else original=result end
 phases[#phases+1]={phase=mode,generation_validation_hash_seconds=generated-t,vector_serialization_seconds=finished-generated,total_seconds=finished-t,lua_bytes_before=math.floor(before),lua_bytes_after=math.floor(collectgarbage('count')*1024),instance_bytes=#result.bytes.instance,scene_bytes=#result.bytes.scene,pdf_bytes=#pdf,svg_bytes=#svg,instance_sha256=result.record.outputs[1].sha256,scene_sha256=result.record.outputs[2].sha256,budgets=P.plain(result.record.budgets),solver=result.record.extensions and result.record.extensions.solver or nil}
 print('Measured',family,mode,string.format('%.6f',finished-t))
end
if profile then debug.sethook()end
local rows=P.array();for name,n in pairs(samples)do rows[#rows+1]={file=name,samples=n}end;table.sort(rows,function(a,b)return a.samples>b.samples end)
local output={status='passed',family=family,source_digest=env.source.digest,actual_lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/performance34',measurement_clock=_bench_wall and 'Python time.perf_counter wall seconds'or 'os.clock CPU estimate; platform semantics apply',bootstrap_source_loading_and_hash_seconds=initialized-first,process_host_elapsed_seconds=_bench_started and clock()-_bench_started or nil,profiled=profile,sampling_interval_instructions=profile and 100000 or nil,sampled_instructions=profile and instructions or nil,sampled_lua_heap_max_bytes=profile and math.floor(peak)or nil,instruction_sample_attribution=rows,phases=phases,scope='Actual unmodified core calls and vector serialization; sampled heap is not whole-process memory or an exact peak. Profile timing has hook overhead; unprofiled timing is measured separately. Semantic output digests are read from the actual Build record, avoiding extra evidence-only hashes during profiling. No TeX/other-device latency claim.'}
fs.mkdir('build');fs.mkdir('build/performance');local filename='build/performance/probe-'..family..'-'..(profile and 'profile'or 'timing')..'-'.._VERSION:gsub(' ','-')..'.json';local f=assert(io.open(filename,'wb'));f:write(P.serialize(output));f:close();return output
