local P,R,Q=require("pattern"),require("pattern_registry"),require("pattern_recipe")
local M,F,V,H,A=require("pattern_stroke"),require("pattern_stroke_field"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local bytes=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name],hashes[name]=bytes,H.sha256(bytes)
end
for n in fs.dir(".") do if n:match("%.lua$") then read(n) end end
read("tools/strokecheck.lua");read("tools/stroke_oracle.py")
local digest=H.value("stroke/source",hashes)
local out="build/strokes/"..digest
for _,p in ipairs{"build","build/strokes",out} do fs.mkdir(p) end
local hashes_out={}
local function write(name,bytes) hashes_out[name]=A.write(out.."/"..name,bytes) end
local reg=R.new()
local d=M.register(reg)
local env=Q.environment({revision="working/stroke/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},{id=V.VERSION,version="1"})
local checks=0
local function check(ok,msg) assert(ok,msg);checks=checks+1 end
local bounds={0,0,6,4}
local holes={{center={3,2},radius=.55},{center={4.75,2.9},radius=.34}}
local data=P.array()
local function stroke(group,p,width,color)
  data[#data+1]={group=group,points=p,width=width,color=color}
end
for j=0,2 do
  for i=0,3 do
    local x,y=.8+i*.56,.9+j*.64
    local group,color,dx,dy
    if i==3 then
      stroke("points",{{x-.021,y}},.044,{.15,.34,.37})
      stroke("points",{{x+.021,y+.014}},.035,{.15,.34,.37})
    else
      if i<2 then group,color,dx,dy="slanted",{.14,.29,.4},.29,.19
      else group,color,dx,dy="upright",{.39,.19,.2},.075,.34 end
      stroke(group,{{x-dx/2,y-dy/2},{x,y}},.032+j*.004,color)
      stroke(group,{{x+dx*.12,y+dy*.12},{x+dx/2,y+dy/2}},.032+j*.004,color)
    end
  end
end
local function recipe(name,params,field,ex,regions)
  return Q.from_specification(d,{id="stroke/"..name,definition_ref={id=d.id,version=d.version},seed=22,
    parameters=params,inputs={field=field,holes=regions,example=ex},style={},constraints={},
    budget={objects=85000,operations=32000000,bytes=64*1024*1024},document={unit="cm",bounds=bounds,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=bounds,protected_regions=P.array(),derived=false,validity="construction_preserved"},2)
end
local function run(q)
  return Q.execute(Q.decode(Q.encode(q)),reg,env)
end
local function build(name,q)
  local result=run(q)
  assert(result.record.status=="complete",name..": "..P.serialize(result.record.diagnostics))
  local x=result.instance
  local e=x.extensions.stroke
  assert(#e.strokes>0,name.." empty")
  check(P.serialize(run(q).instance)==P.serialize(x),"determinism "..name)
  local plan=V.plan(result.scene,x,result.view,d)
  write(name..".instance",P.serialize(x))
  write(name..".recipe",Q.encode(q))
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
  print(name,#e.strokes)
  return e
end
local radial=F.new(bounds,{}, {direction="radial",origin={3,2}})
check(F.integrate(radial,{3,2},.10,8,0).stop=="singularity","origin singularity")
check(F.integrate(radial,{3.05,2},.10,8,0,{reverse=true}).stop=="singularity","no splice across singularity")
local circular=F.new(bounds,{}, {direction="vortex",origin={3,2}})
local integrated=F.integrate(circular,{4,2},.02,60,0)
for _,p in ipairs(integrated.points) do
  assert(math.abs((p[1]-3)^2+(p[2]-2)^2-1)<.0001,"vortex radius drift")
end
check(integrated.stop=="step_budget" and #integrated.points==61,"bounded vortex")
local hatch=build("hatch",recipe("hatch",{mode="hatching",spacing=.21,step=.065,steps=38,count=45}, {direction="vortex"},nil,holes))
local stopped={}
for _,s in ipairs(hatch.trace.stops) do stopped[s.forward]=true;stopped[s.backward]=true end
check(stopped.boundary and stopped.hole and stopped.separation,"hatch termination coverage")
local dots={mode="stippling",spacing=.096,width=.058,count=185,attempts=4000}
local tone=build("tone",recipe("tone",dots,{direction="uniform",density={.10,1}},nil,holes))
local flat=build("uniform",recipe("uniform",dots,{direction="uniform",density={1,1}},nil,holes))
check(#tone.strokes==185 and #flat.strokes==185,"stippling matched count")
local function synth(name,profile,behavior,scale)
  return build(name,recipe(name,{mode="example",spacing=.51,count=65,profile=profile,behavior=behavior,
    scale=scale,cluster=.10,radius=.94,threshold=.85,correction=.34,relax=4},
    {direction="uniform"},data,holes))
end
local causal=synth("causal","causal","cloning",1)
local baseline=synth("independent","independent","cloning",1)
local cloning=synth("cloning","group","cloning",1)
local copying=synth("copying","group","copying",1)
local sampling=synth("sampling","group","sampling",1)
local scaled=synth("scaled","group","cloning",1.35)
check(#causal.trace.analysis.merges==12 and #causal.trace.analysis.elements==12,"example clusters")
check(P.serialize(causal.trace.elements)~=P.serialize(baseline.trace.elements),"neighborhood had no effect")
local matched,corrected=0,0
for _,v in ipairs(causal.trace.decisions) do if v.kept and v.matched>0 and not v.fallback then matched=matched+1 end end
for _,v in ipairs(cloning.trace.decisions) do if v.kept and v.pair then corrected=corrected+1 end end
check(matched>=10 and corrected>=10,"causal matching and pair correction")
check(P.serialize(cloning.trace.elements)~=P.serialize(copying.trace.elements)
  and P.serialize(copying.trace.elements)~=P.serialize(sampling.trace.elements),"distinct behaviors")
check(P.serialize(scaled.trace.elements)~=P.serialize(cloning.trace.elements),"scale has no effect")
local invalid=P.plain(data)
invalid[1].points[2]=P.plain(invalid[1].points[1])
local failed=run(recipe("invalid",{mode="example",spacing=.51,count=65},{direction="uniform"},invalid,holes))
check(failed.record.status~="complete","invalid example accepted")
A.write(out.."/receipt.json",P.serialize({stage="22",checks=checks,source_digest=digest,outputs=hashes_out,
  matched=matched,corrected=corrected,terminations=stopped}))
print("Stroke checks passed",checks,digest,matched,corrected)

