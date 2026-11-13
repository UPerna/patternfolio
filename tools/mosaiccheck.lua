local P,R,Q,E=require("pattern"),require("pattern_registry"),require("pattern_recipe"),require("pattern_examples")
local F,V,H,A=require("pattern_mosaic"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local sources,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"))
  local bytes=f:read("*a"):gsub("\r\n","\n")
  f:close()
  sources[name],hashes[name]=bytes,H.sha256(bytes)
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
read("tools/mosaiccheck.lua");read("tools/mosaic_oracle.py")
local digest=H.value("mosaic/source",hashes)
local root="build/mosaic/"..digest
for _,path in ipairs{"build","build/mosaic",root} do fs.mkdir(path) end
local outputs={}
local function write(name,bytes) outputs[name]=A.write(root.."/"..name,bytes) end
local reg=R.new()
local d=F.register(reg)
local limits={objects=50000,operations=48000000,bytes=64*1024*1024}
local env=Q.environment({revision="working/mosaic/"..digest,files={construction=sources,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=V.VERSION,version="1"})
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local bounds={0,0,6,4}
local curve={}
for i=0,36 do
  local x=i/6
  curve[i+1]={x,1.22+.26*(x-3)^2}
end
local image={background={.15,.32,.48},layers={
  {shape="band",center={3,1.62},extent={3,.34},curve=.26*9/.34,color={.25,.62,.59}},
  {shape="band",center={3,1.52},extent={3,.14},curve=.26*9/.14,color={.76,.84,.65}},
  {shape="ellipse",center={3,2.95},extent={.72,.63},color={.92,.65,.29}}}}
local simple={background={.20,.39,.52},layers={
  {shape="ellipse",center={3,2},extent={1.68,1.29},color={.87,.63,.26}},
  {shape="ellipse",center={3.1,2.09},extent={.75,.6},color={.97,.84,.56}}}}
local panel={{.25,1},{1.25,.18},{4.72,.12},{5.85,1.16},{5.5,3.3},{4.46,3.92},{1.54,3.8}}
local function recipe(name,opts)
  return Q.from_specification(d,{id="mosaic/"..name,definition_ref={id=d.id,version=d.version},seed=21,
    parameters={count=opts.count or 143,tile_size=opts.size or .38,sample_step=.12,
      guided=opts.guided~=false,iterations=opts.iterations or 18,avoid_steps=opts.avoid_steps or 8,
      exclusion=opts.exclusion or .14,influence=1.05,aspect=1.58,size_variation=.13,
      grout=.022,min_scale=opts.min_scale or .22},
    inputs={features=opts.features or P.array(),image=opts.image or image,panel=opts.panel,witness=opts.witness},
    constraints={},style={},budget=limits,document={unit="cm",bounds=bounds,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=bounds,protected_regions=P.array(),derived=false,
      validity="construction_preserved"},2)
end
local function run(q)
  return Q.execute(Q.decode(Q.encode(q)),reg,env)
end
local function complete(q)
  local result=run(q)
  assert(result.record.status=="complete",P.serialize(result.record.diagnostics))
  return result
end
local cases={{"analytic",{image=simple}},{"baseline",{features={curve},guided=false}},
  {"curved",{features={curve}}},{"irregular",{features={curve},panel=panel,count=116}}}
for _,case in ipairs(cases) do
  local name,options=table.unpack(case)
  local q=recipe(name,options)
  local result=complete(q)
  local x=result.instance
  local e=x.extensions.mosaic
  check(#e.packing.tiles>e.request.count*.8 and e.packing.coverage>.35,"low coverage: "..name)
  check(e.solver.evaluations==#e.solver.history+1 and e.solver.final_energy>0,"missing iteration trace")
  check(P.serialize(complete(q).instance)==P.serialize(x),"determinism")
  local saved=P.plain(options)
  saved.witness,saved.iterations=P.plain(e.centers),0
  local replay=complete(recipe(name.."-saved",saved))
  check(replay.instance.id==x.id and replay.bytes.scene==result.bytes.scene and replay.record.extensions.solver.evaluations==0,
    "solver-free replay changed geometry")
  write(name..".recipe",Q.encode(q))
  write(name..".instance",P.serialize(x))
  local plan=V.plan(result.scene,x,result.view,d)
  write(name..".pdf",V.pdf(plan))
  write(name..".svg",V.svg(plan))
  if name=="curved" then
    local context=R.context({seed=21,frame=P.plain(x.frame),source={revision="working/mosaic/"..digest},limits=limits})
    local v=E.view(x,d,{1.5,1.0,4.5,2.5})
    local scene=reg:lower(d.id,x,v,{features=true},context)
    local plan=V.plan(scene,x,v,d)
    write("detail.pdf",V.pdf(plan));write("detail.svg",V.svg(plan))
  end
  print(name,#e.packing.tiles,e.packing.coverage,e.solver.status,e.solver.final_energy)
end
local early=complete(recipe("early",{iterations=0,features={curve}}))
check(early.record.extensions.solver.status=="iteration_budget" and #early.record.extensions.solver.history==0,"zero budget")
local starved=complete(recipe("starved",{iterations=3,features={curve},exclusion=4}))
check(starved.record.extensions.solver.status=="no_active_samples","masked sampling failure")
local tight=complete(recipe("tight",{features={curve},panel=panel,count=65,size=3,min_scale=1,iterations=1}))
check(#tight.instance.extensions.mosaic.packing.rejected>=60 and tight.instance.extensions.mosaic.packing.status~="all_sites_packed","boundary rejection")
local invalid=run(recipe("invalid",{features={{{1,1},{1,1}}}}))
check(invalid.record.status~="complete","zero feature segment admitted")
write("failure-cases.json",P.serialize({early=early.record.extensions.solver,starved=starved.record.extensions.solver,
  tight=tight.instance.extensions.mosaic.packing}))
A.write(root.."/receipt.json",P.serialize({stage="21",source_digest=digest,checks=checks,outputs=outputs}))
print("Mosaic checks passed",checks,digest)


