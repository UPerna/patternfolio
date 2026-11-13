local P,R,Q,E=require("pattern"),require("pattern_registry"),require("pattern_recipe"),require("pattern_examples")
local F,T,C,K=require("pattern_escher"),require("pattern_escher_metric"),
  require("pattern_escher_periodic"),require("pattern_escher_p3")
local V,H,A=require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local Parse=require("pattern_parse")
local fixture="docs/validation/fixtures/escher-targets.json"
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local data=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name]=data;hashes[name]=H.sha256(data)
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
for _,name in ipairs{fixture,"tools/eschercheck.lua","tools/escher_oracle.py"} do read(name) end
local digest=H.value("escher/source",hashes)
local root="build/escher/"..digest
for _,path in ipairs{"build","build/escher",root} do fs.mkdir(path) end
local outputs={}
local function write(name,data) outputs[name]=A.write(root.."/"..name,data) end
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local reg=R.new()
local d=F.register(reg)
local limits={objects=50000,operations=48000000,bytes=64*1024*1024}
local env=Q.environment({revision="working/escher/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=V.VERSION,version="1"})
local inputs=Parse.decode(source[fixture])
local windows={periodic={-.1,-.1,4.1,3.1},split={-.1,-.1,4.1,3.1},penrose={-2,-1.5,2.5,1.7}}
local function recipe(name,profile,box,steps,targets,witness)
  return Q.from_specification(d,{id="escher/"..name,definition_ref={id=d.id,version=d.version},seed=20,
    parameters={profile=profile,edge_length=profile=="penrose" and .45 or 1,steps=steps},
    inputs={targets=targets,witness=witness},constraints={},style={},budget=limits,
    document={unit="cm",bounds=box,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=box,protected_regions=P.array(),
      derived=false,validity="construction_preserved"},2)
end
local function execute(q)
  return Q.execute(Q.decode(Q.encode(q)),reg,env)
end
local function render(name,x,box,display)
  local context=R.context({seed=20,frame=P.plain(x.frame),source={revision="working/escher/"..digest},limits=limits})
  local v=E.view(x,d,box)
  local scene=reg:lower(d.id,x,v,{display=display},context)
  local plan=V.plan(scene,x,v,d)
  local a,b=V.pdf(plan),V.svg(plan)
  write(name..".pdf",a);write(name..".svg",b)
  return a,b
end
local function success(q)
  local x=execute(q)
  assert(x.record.status=="complete",P.serialize(x.record.diagnostics))
  return x
end
local t=inputs.periodic[1]
local shifted={}
for i=1,#t do
  local p=t[(i+4)%#t+1]
  shifted[i]={7-3*p[2],-4+3*p[1]}
end
check(T.distance(T.turning(t),T.turning(shifted))<1e-7,"turning metric lost rigid/scale/cyclic invariance")
local mirror={}
for i=#t,1,-1 do mirror[#mirror+1]={-t[i][1],t[i][2]} end
check(T.distance(T.turning(t),T.turning(mirror))>.01,"asymmetric target orientation was erased")

local models,instances={},{}
for _,name in ipairs{"periodic","split","penrose"} do
  local box=windows[name]
  local q=recipe(name,name,box,name=="split" and 360 or 140,inputs[name])
  local result=success(q)
  local x=result.instance
  local e=x.extensions.escher
  instances[name]=x
  local solver=result.record.extensions.solver
  check(solver.score<solver.baseline*.98 and solver.improvements>0,"insufficient objective improvement: "..name)
  check(solver.score>1e-4 and #solver.errors==#inputs[name],"missing residual mismatch: "..name)
  local replay_recipe=recipe(name.."-replay",name,box,0,inputs[name],P.plain(e.values))
  local replay=success(replay_recipe)
  check(replay.instance.id==x.id and replay.bytes.scene==result.bytes.scene
    and replay.record.extensions.solver.route=="replayed" and replay.record.extensions.solver.evaluations==1,
    "recorded witness changed the output")
  write(name..".recipe",Q.encode(q))
  write(name.."-replay.recipe",Q.encode(replay_recipe))
  write(name..".instance",result.bytes.instance)
  write(name.."-solver.json",P.serialize(solver))
  render(name,x,box,"design");render(name.."-baseline",x,box,"scaffold")
  local baseline,optimized
  if name=="penrose" then baseline,optimized=K.baseline(),K.shapes(e.values)
  else
    baseline=C.shapes(C.domain(name=="split"),e.request)
    optimized=C.shapes(e.values,e.request)
  end
  models[name]={baseline=baseline,optimized=optimized,targets=inputs[name],witness=P.plain(e.values)}
  if name=="periodic" then
    local again=success(q)
    check(again.bytes.instance==result.bytes.instance and again.bytes.scene==result.bytes.scene,
      "same seed altered the annealing result")
  end
end
write("prototype-models.json",P.serialize(models))
local x=instances.penrose
local e=x.extensions.escher
local other_box={-1.2,-1.1,3,2.5}
local other=success(recipe("penrose-offset","penrose",other_box,0,inputs.penrose,P.plain(e.values))).instance
render("penrose-offset",other,other_box,"design")
local common={-.9,-.9,2,1.4}
local a,b=render("common-a",x,common,"design")
local c,f=render("common-b",other,common,"design")
check(a==c and b==f,"coupled geometry moved with the query")
local edges={}
for _,edge in ipairs(x.structures.tiling.edges) do edges[edge.id]=edge end
local shared=0
for _,edge in ipairs(other.structures.tiling.edges) do
  local prior=edges[edge.id]
  if prior and prior.role=="interior" and edge.role=="interior" then
    assert(P.serialize(prior.path)==P.serialize(edge.path) and P.serialize(prior.incidence)==P.serialize(edge.incidence),
      "coupled seam identity changed")
    shared=shared+1
  end
end
check(shared>100,"overlapping queries do not exercise shared seams")
write("penrose-offset.instance",P.serialize(other))
write("penrose-source.instance",P.serialize(e.scaffold))
check(e.certificate.source_sha256==H.sha256(P.serialize(e.scaffold)),"source scaffold digest mismatch")
local limited=execute(recipe("limited","periodic",windows.periodic,0,inputs.periodic))
check(limited.record.status=="failed" and limited.record.extensions.solver.status=="limited"
  and #limited.record.outputs==0,"limited solve yielded paint")
local impossible=execute(recipe("noncontractive","periodic",windows.periodic,0,inputs.periodic,{82,-82,82,82,-82,82}))
check(impossible.record.status=="failed" and impossible.record.extensions.solver.status=="inadmissible_witness",
  "noncontractive edge deformation was accepted")
local no_improvement=execute(recipe("already-exact","periodic",windows.periodic,12,
  {{{0,0},{1,0},{1,1},{0,1}}}))
check(no_improvement.record.status=="failed" and no_improvement.record.extensions.solver.status=="no_improvement",
  "zero-residual target was misreported as improved")
local invalid=execute(recipe("self-intersection","periodic",windows.periodic,12,
  {{{0,0},{1,1},{0,1},{1,0}}}))
check(invalid.record.status=="failed" and #invalid.record.outputs==0,"crossed target accepted")
local corrupt=P.plain(x)
corrupt.structures.tiling.edges[1].class=100
check(not pcall(F.validate,corrupt),"forged Penrose edge class accepted")
write("solver-failures.json",P.serialize({limited=P.plain(limited.record.extensions.solver),
  inadmissible=P.plain(impossible.record.extensions.solver),unimproved=P.plain(no_improvement.record.extensions.solver),
  invalid_target=P.plain(invalid.record.diagnostics)}))
A.write(root.."/receipt.json",P.serialize({stage="20",source_digest=digest,checks=checks,outputs=outputs,shared_edges=shared}))
print("Escherization: "..checks.." checks; "..shared.." common exact P3 edges")
