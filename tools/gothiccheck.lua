local P,R,Q=require("pattern"),require("pattern_registry"),require("pattern_recipe")
local G,V,H,A=require("pattern_gothic_microarchitecture"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"))
  local bytes=f:read("*a"):gsub("\r\n","\n")
  f:close()
  source[name],hashes[name]=bytes,H.sha256(bytes)
end
for n in fs.dir(".") do if n:match("%.lua$") then read(n) end end
read("tools/gothiccheck.lua")
read("tools/gothic_oracle.py")
local digest=H.value("gothic/source",hashes)
local folder="build/gothic/"..digest..(PATTERN_TEST_VARIANT or "")
for _,p in ipairs{"build","build/gothic",folder} do fs.mkdir(p) end
local outputs={}
local function write(name,bytes) outputs[name]=A.write(folder.."/"..name,bytes) end
local reg=R.new()
local d=G.register(reg)
local env=Q.environment({revision="working/gothic/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},{id=V.VERSION,version="1"})
local bounds={0,0,9,9.5}
local top={1,0,0,.6,0,1,0,3,0,0,1,0,0,0,0,1}
local front={1,0,0,.6,0,0,1,.6,0,-1,0,0,0,0,0,1}
local oblique={.8,-.6,0,1,.36,.48,.8,2,-.48,-.64,.6,0,0,0,0,1}
local main={origin={.5,1.1},radius=5,start=1,finish=4.5,height=4.5,
  replicas={{0,8,1,-1},{.4,7.7,1,-1}}}
local small={parent=1,radius=2,start=.4,finish=1.7,height=1.65,
  replicas={{0,3.2,1,-1}}}
local function recipe(name,matrix,policy,units)
  return Q.from_specification(d,{id="gothic/"..name,definition_ref={id=d.id,version=d.version},seed=26,
    parameters={tolerance=.003},inputs={units=units},style={},constraints={},
    budget={objects=25000,operations=250000,bytes=32*1024*1024},
    document={unit="cm",bounds=bounds,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=bounds,protected_regions=P.array(),derived=true,
      validity="visualization_only",projection={matrix=matrix,depth_policy=policy}},3)
end
local function render(name,matrix,policy,units)
  local q=recipe(name,matrix,policy,units)
  local result=Q.execute(Q.decode(Q.encode(q)),reg,env)
  assert(result.record.status=="complete",P.serialize(result.record.diagnostics))
  local x=result.instance
  local plan=V.plan(result.scene,x,result.view,d)
  write(name..".recipe",Q.encode(q))
  write(name..".view",P.serialize(result.view))
  write(name..".scene",P.serialize(result.scene))
  write(name..".pdf",V.pdf(plan))
  write(name..".svg",V.svg(plan))
  return G.export(x),x
end
local network,x=render("top",top,"all_curves",{main,small})
write("canonical.network.json",network)
assert(render("front",front,"all_curves",{main,small})==network,"front altered spatial network")
assert(render("oblique",oblique,"depth_sorted",{main,small})==network,"oblique altered spatial network")
local revised=P.plain(main)
revised.height=5.3
local edit,y=render("edited",oblique,"depth_sorted",{revised,small})
write("edited.network.json",edit)
assert(y.extensions.gothic_spatial.units[2].origin[3]-x.extensions.gothic_spatial.units[2].origin[3]>.79)
assert(x.extensions.gothic_spatial.units[1].crossings[1].joined)
local false_crossing=false
for _,q in ipairs(x.extensions.gothic_spatial.units[1].crossings) do
  false_crossing=false_crossing or not q.joined
end
assert(false_crossing,"missing independent depth witness")
local flat=P.plain(main)
flat.height=3.2
local unjoined=P.plain(main)
unjoined.replicas={{0,1,1,-1}}
local bad_camera=P.plain(top)
bad_camera[1]=2
for _,case in ipairs({
  {name="side",units={flat},matrix=top,diagnostic="gothic-side-chart"},
  {name="crossing",units={unjoined},matrix=top,diagnostic="gothic-missing-interior"},
  {name="camera",units={main},matrix=bad_camera,diagnostic="gothic-orthonormal-camera"},
}) do
  local r=Q.execute(recipe(case.name,case.matrix,"all_curves",case.units),reg,env)
  assert(r.record.status~="complete" and P.serialize(r.record.diagnostics):find(case.diagnostic,1,true),
    P.serialize(r.record.diagnostics))
end
write("receipt.json",P.serialize({source_digest=digest,checks=8,outputs=outputs}))
