-- Real generation/replay, independent golden vectors, cache mutation and filesystem faults.
local P,H,D,Q,E,R=require("pattern"),require("pattern_hash"),require("pattern_random"),require("pattern_recipe"),require("pattern_examples"),require("pattern_registry")
local Parse=require("pattern_parse");local lfs=require("lfs");local n=0
local function check(ok,why) assert(ok,why);n=n+1 end
local function reject(fn) check(not pcall(fn),"expected useful rejection") end
local function read(p) local f=assert(io.open(p,"rb"));local b=f:read("*a");f:close();return b end
local vectors=Parse.decode(read("docs/validation/fixtures/determinism-v1.json"))
for _,v in ipairs(vectors.sha256) do
  local bytes=v.text or (v.hex and v.hex:gsub('..',function(h)return string.char(tonumber(h,16))end)) or string.rep(v.repeat_text,v.count)
  check(H.sha256(bytes)==v.sha256,"independent SHA-256 vector "..v.name)
end
for _,v in ipairs(vectors.numbers) do check(P.serialize(tonumber(v.input))==v.canonical,"canonical number "..v.input) end
check(P.serialize({z=1,a=2,["α"]=3})==vectors.sorted_object,"bytewise object ordering")
local r=D.new(1);for i=1,10000 do r.next_integer() end
check(r.save()==1043618065,"published 10000th Park/Miller vector")
for _,v in ipairs(vectors.streams) do
  check(D.seed(v.root,v.namespace,v.name,v.semantic_id)==v.seed,"independent named seed")
  local s=D.new(v.seed);for _,value in ipairs(v.first) do check(s.next_integer()==value,"named stream golden word") end
end
check(H.bytes("a","bc")~=H.bytes("ab","c"),"domain framing is unambiguous")
local a,b=D.provider(7,"fixture"),D.provider(7,"fixture")
local x=a("geometry","node/1",7).next_integer();a("visitors","bee/1",7).next_integer()
check(x==b("geometry","node/1",7).next_integer(),"unrelated stream does not consume geometry")
check(a("geometry","node/1",7).next_integer()==b("geometry","node/1",7).next_integer(),"same stream retains state")
local function floral_context() return R.context({seed=7,source={revision="real-primitives-fixture"},stream_provider=D.provider(7,"fixture/floral@1")}) end
local ff=dofile("tools/fixtures/replay-floral.lua")
local without,with=ff.construct(floral_context(),false),ff.construct(floral_context(),true)
for _,id in ipairs({"plant/root/flower/0","plant/root/flower/1"}) do
  check(P.serialize(without.resources[id])==P.serialize(with.resources[id]) and #with.resources[id].content>1000,"real flower output independent of optional bee")
end
check(with.resources["visitors/bee/0"] and #with.nodes==3 and #without.nodes==2,"actual optional visitor output exists")
reject(function() D.seed(7,"fixture",nil,"id") end)
reject(function() D.new(0) end)
reject(function() D.new(1).range(-1e308,1e308) end)
local registry,defs=E.registry();local recipes={}
for _,name in ipairs({"floral","graph","tiling"}) do
  local d=defs[name];local c=R.context({seed=7,source={revision="fixture"}});local built=assert(registry:generate(d.id,E.specification(d),c))
  recipes[name]=Q.from_specification(d,E.specification(d),E.view(built.instance,d),2)
end
local sources={construction={},style={},view={},renderer={}}
for name in lfs.dir(".") do if name:match('%.lua$') then sources.construction[name]=read(name) end end
sources.construction["tools/replaycheck.lua"]=read("tools/replaycheck.lua")
sources.construction["tools/fixtures/replay-floral.lua"]=read("tools/fixtures/replay-floral.lua")
sources.style["fixture-paint"]="rgb-paint-v1";sources.view["fixture-view"]="affine-view-v1";sources.renderer["fixture-renderer"]="scene-json-v1"
local runtime={lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported"),numeric_profile="int64-binary64"}
print("replaycheck runtime: ".._VERSION.."; "..runtime.host.."; "..tostring(lfs._VERSION or "injected atomic directory adapter").."; int64/binary64")
local env=Q.environment({revision="working-source/"..H.value("fixture/source",sources),files=sources},runtime,{id="scene-json",version="1"})
for name,recipe in pairs(recipes) do
  check(Q.encode(Q.decode(Q.encode(recipe)))==Q.encode(recipe),"recipe roundtrip "..name)
  local first=Q.execute(recipe,registry,env);local again=Q.execute(recipe,registry,env)
  check(first.record.status=="complete" and again.record.status=="complete","actual build "..name)
  check(first.bytes.instance==again.bytes.instance and first.bytes.scene==again.bytes.scene,"actual deterministic replay "..name)
  check(first.record.outputs[1].sha256==H.sha256(first.bytes.instance) and first.record.outputs[2].sha256==H.sha256(first.bytes.scene),"output byte binding")
  check(first.record.source.digest==H.value("source/manifest",env.source.files),"exact source manifest binding")
end
local recipe=recipes.tiling;local base=Q.execute(recipe,registry,env)
local input_recipe=P.plain(recipes.graph);local data='{"x":0.25}'
input_recipe.design.inputs={resource="data"};input_recipe.dependencies.construction.data={sha256=H.sha256(data),version="fixture-input-1"};input_recipe=Q.new(input_recipe)
reject(function()Q.execute(input_recipe,registry,env)end)
local wrong=Q.environment({revision=env.source.revision,files=sources},runtime,{id="scene-json",version="1"},{data="wrong"})
reject(function()Q.execute(input_recipe,registry,wrong)end)
local correct=Q.environment({revision=env.source.revision,files=sources},runtime,{id="scene-json",version="1"},{data=data})
local ir=R.new();local canonical=Q.execute(recipes.graph,registry,env).instance
ir:register(defs.graph,{
  validate_inputs=function(s)return s.inputs.resource=="data"end,
  generate=function(s,c)local v=Parse.decode(c:input("data"));assert(type(v.x)=="number" and v.x>=0 and v.x<=1);local out=P.plain(canonical);out.structures.graph.vertices[1].point[1]=v.x;return out end,
  validate=function(x)return {ok=x.structures.graph.vertices[1].point[1]==0.25,checks={"verified byte input x coordinate"}}end,
  lower=function(x,v,s,c)return P.plain(registry:lower(defs.graph.id,x,v,s,c))end,
})
local input_build=Q.execute(input_recipe,ir,correct)
check(input_build.record.status=="complete" and input_build.instance.structures.graph.vertices[1].point[1]==0.25,"actual verified input consumed in geometry")
check(input_build.record.inputs[2].id=="data" and input_build.record.inputs[2].sha256==H.sha256(data),"input byte digest bound in build record")
local changed=P.plain(recipe);changed.design.style.fill={1,0,0};local palette=Q.execute(Q.new(changed),registry,env)
check(base.bytes.instance==palette.bytes.instance and base.bytes.scene~=palette.bytes.scene,"real palette change preserves topology and geometry")
changed=P.plain(recipe);changed.view.crop={0.5,0.1,1.5,0.9};local crop=Q.execute(Q.new(changed),registry,env)
check(base.bytes.instance==crop.bytes.instance and crop.scene.clip.bounds[1]==0.5,"overlapping crop preserves exact tile IDs and geometry")
local function mutation(group,change,expected)
  local t=P.plain(recipe);change(t);t=Q.new(t);local before=Q.cache_keys(recipe,env);local after=Q.cache_keys(t,env)
  for _,k in ipairs({"structure","style","view","renderer"}) do check((before[k]~=after[k])==not not expected[k],group.." invalidation "..k) end
end
mutation("palette",function(t)t.design.style.fill={1,0,0}end,{style=true,renderer=true})
mutation("crop",function(t)t.view.crop={0,0,1,1}end,{view=true,renderer=true})
for _,g in ipairs({"construction","style","view","renderer"}) do
  local expected={renderer=true};if g=="construction" then expected.structure=true;expected.style=true;expected.view=true elseif g=="style" then expected.style=true elseif g=="view" then expected.view=true end
  mutation(g,function(t)t.dependencies[g].test={sha256=H.sha256("changed"),configuration={mode="new"}}end,expected)
end
local with_font=P.plain(recipe);with_font.dependencies.construction.font={sha256=H.sha256("font bytes"),configuration={script="Grek",features="kern"}};with_font=Q.new(with_font)
local fontkey=Q.cache_keys(with_font,env).structure
for _,what in ipairs({"bytes","shaping","solver"}) do
  local t=P.plain(with_font)
  if what=="bytes" then t.dependencies.construction.font.sha256=H.sha256("different font bytes")
  elseif what=="shaping" then t.dependencies.construction.font.configuration.features="-kern"
  else t.dependencies.construction.solver={sha256=H.sha256("solver result"),version="solver-1"} end
  check(Q.cache_keys(Q.new(t),env).structure~=fontkey,what.." dependency invalidates structure")
end
local rt=P.plain(runtime);rt.host=rt.host.."-changed";local env2=Q.environment({revision=env.source.revision,files=sources},rt,{id="scene-json",version="1"})
check(Q.cache_keys(recipe,env).structure~=Q.cache_keys(recipe,env2).structure,"runtime invalidation")
env2=Q.environment({revision=env.source.revision,files=sources},runtime,{id="scene-json",version="2"})
local k1,k2=Q.cache_keys(recipe,env),Q.cache_keys(recipe,env2)
check(k1.structure==k2.structure and k1.style==k2.style and k1.view==k2.view and k1.renderer~=k2.renderer,"renderer-only version invalidation")
local failed=Q.execute(recipe,registry,env,{limits={objects=1,operations=10,bytes=1000}})
check(failed.record.status=="failed" and not failed.instance and #failed.record.outputs==0,"budget failure build record")
check(failed.keys.structure~=base.keys.structure,"observed execution limits are hashed dependencies")
local cancelled=Q.execute(recipe,registry,env,{cancelled=function()return true end})
check(cancelled.record.status=="cancelled" and not cancelled.scene,"cancelled build never accepted")
check(cancelled.record.id~=base.record.id,"different outcome has a distinct reproducible record identity")
local polls=0;local late=Q.execute(recipe,registry,env,{cancelled=function()polls=polls+1;return polls>=3 end})
check(late.record.status=="cancelled" and not late.scene and #late.record.outputs==0,"late cancellation discards lowered partial output")
local bad_style=P.plain(recipe);bad_style.design.style.unsupported=1
local lower_failed=Q.execute(Q.new(bad_style),registry,env)
check(lower_failed.record.status=="failed" and not lower_failed.instance and #lower_failed.record.outputs==0,"lowering failure does not publish a partial build")
local partial=P.plain(failed.record);partial.status="partial";check(P.build_record(partial).status=="partial","explicit partial status")
local migrated,receipt=Q.migrate(recipe,1);check(Q.encode(migrated)==Q.encode(recipe) and receipt.from==1,"explicit identity validation")
for _,change in ipairs({function(t)t.schema_version=0 end,function(t)t.design.seed=0/0 end,function(t)t.design.parameters.unsupported=1 end,function(t)t.design.document.unit="pt" end,function(t)t.view.transform={2,0,0,1,0,0} end,function(t)t.unrecognized=true end}) do
  local t=P.plain(recipe);change(t);reject(function()Q.new(t)end)
end
reject(function()local t=P.plain(recipe);t.schema_version=0;Q.migrate(t,1)end)
for _,bad in ipairs({'{"a":1,"a":2}','{"a":1,"\\u0061":2}','[1 2]','[1,]','{"a":1,}','01','+1','1.','1e','1e9999','NaN','/*x*/{}','null','"\\uD800"','"\\uDC00"','"\\x41"','true false','"line\nfeed"'}) do reject(function()Parse.decode(bad)end) end
reject(function()Parse.decode('"'..string.char(0xed,0xa0,0x80)..'"')end)
reject(function()P.serialize({[string.char(0xed,0xa0,0x80)]=1})end)
local old_numeric=os.setlocale(nil,"numeric");local locales=0
for _,name in ipairs({"C","German_Germany.1252","de_DE.UTF-8"}) do
  if os.setlocale(name,"numeric") then locales=locales+1;check(P.serialize(0.1)=="0.10000000000000001" and Parse.decode('0.1')==0.1,"locale-independent decimal") end
end
os.setlocale(old_numeric,"numeric")
print("replaycheck: numeric locales exercised "..locales.."; unavailable locales skipped explicitly")
check(Parse.decode('"\\uD83C\\uDF38"')=="🌸","valid surrogate pair")
-- Real local filesystem publication: incomplete, corrupt, busy and failed rename cases.
lfs.mkdir("build");local scratch="build/replay-"..tostring(os.time()).."-"..tostring({}):gsub('[^%w]','')
assert(lfs.mkdir(scratch));local store=require("pattern_store").new(scratch);local key=base.keys.renderer
check(store:put(key,base.bytes.scene),"atomic cache publication")
check(store:get(key)==base.bytes.scene,"verified cache replay")
local ok=store:put(key,"different");check(not ok and store:get(key)==base.bytes.scene,"nondeterministic collision preserves original")
local corrupt=H.sha256("corrupt");local f=assert(io.open(scratch.."/"..corrupt..".json","wb"));f:write('{"payload":');f:close()
check(not store:get(corrupt) and not store:put(corrupt,"{}"),"partial entry rejected and preserved")
local busy=H.sha256("busy");assert(lfs.mkdir(scratch.."/"..busy..".json.lock"));check(not store:put(busy,"{}"),"active or stale lock is explicit")
local failkey=H.sha256("failed-rename");local host={mkdir=lfs.mkdir,rmdir=lfs.rmdir,open=io.open,remove=os.remove,rename=function() return nil,"injected rename failure" end}
local faulty=require("pattern_store").new(scratch,host)
check(not faulty:put(failkey,"{}") and not store:get(failkey),"rename failure leaves no accepted entry")
local stray=H.sha256("temporary-only");assert(lfs.mkdir(scratch.."/"..stray..".json.lock"));f=assert(io.open(scratch.."/"..stray..".json.lock/payload.tmp","wb"));f:write("half");f:close()
check(not store:get(stray),"reader ignores unfinished temporary bytes")
print("replaycheck: "..n.." checks passed; golden vectors, actual generation/replay, dependency mutations, failure records and atomic filesystem faults")
