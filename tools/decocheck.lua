local P,R,Q=require("pattern"),require("pattern_registry"),require("pattern_recipe")
local M,V,H,A=require("pattern_decobrush"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")

local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local bytes=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name],hashes[name]=bytes,H.sha256(bytes)
end

for n in fs.dir(".") do if n:match("%.lua$") then read(n) end end
read("tools/decocheck.lua");read("tools/check-deco-integration.lua");read("tools/deco_oracle.py")

local digest=H.value("decobrush/source",hashes)
local folder="build/decobrush/"..digest..(PATTERN_TEST_VARIANT or "")
for _,p in ipairs{"build","build/decobrush",folder} do fs.mkdir(p) end
local outputs={}
local function write(name,bytes) outputs[name]=A.write(folder.."/"..name,bytes) end
local reg=R.new()
local d=M.register(reg)
local env=Q.environment({revision="working/decobrush/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},{id=V.VERSION,version="1"})
local checks=0
local function check(ok,msg) assert(ok,msg);checks=checks+1 end

local function rect(left,bottom,right,top)
  return {ring={{left,bottom},{right,bottom},{right,top},{left,top}}}
end

local guide={{.4,.55,.6},{1.4,.59,.6},{2.4,.67,.6},{3.4,.79,.6}}
local bounds={0,0,4,1.5}
local oval_profile={
  {1,0},{.92388,.382683},{.707107,.707107},{.382683,.92388},
  {0,1},{-.382683,.92388},{-.707107,.707107},{-.92388,.382683},
  {-1,0},{-.92388,-.382683},{-.707107,-.707107},{-.382683,-.92388},
  {0,-1},{.382683,-.92388},{.707107,-.707107},{.92388,-.382683},
}
local function oval(cx,cy,rx,ry)
  local ring={}
  for i,p in ipairs(oval_profile) do ring[i]={cx+rx*p[1],cy+ry*p[2]} end
  return {ring=ring}
end
local classes={
  floral={rect(.44,.07,.55,.22),oval(.49,.19,.09,.09),
    oval(.36,.195,.115,.06),oval(.62,.195,.115,.06),
    {ring={{.18,.06},{.23,.17},{.38,.10},{.34,.06}}},
    {ring={{.67,-.05},{.79,-.22},{.92,-.15},{.83,-.075}}}},
  geometric={rect(.26,.08,.32,.245),rect(.68,.08,.74,.245),
    rect(.26,.21,.74,.275),rect(.43,-.24,.57,-.075),
    {ring={{.35,-.16},{.5,-.275},{.65,-.16},{.5,-.09}}}},
  branched={rect(.41,.045,.52,.26),rect(.49,.17,.72,.22),
    rect(.22,-.23,.29,-.075),rect(.06,-.225,.26,-.17),
    rect(.68,-.22,.76,-.07),rect(.72,-.225,.90,-.17)},
}
local function library(branches)
  local middle={rect(-.5,-.1,1.5,.1)}
  for _,branch in ipairs(branches) do middle[#middle+1]=branch end
  return {
    {role="start",length=1,width=.6,turn=0,primitives={rect(.08,-.1,1.5,.1)}},
    {role="middle",length=1,width=.6,turn=0,primitives=middle},
    {role="finish",length=1,width=.6,turn=0,primitives={rect(-.5,-.1,.92,.1)}},
  }
end

local function recipe(name,branches,edit,path)
  return Q.from_specification(d,{id="decobrush/"..name,definition_ref={id=d.id,version=d.version},seed=25,
    parameters={},inputs={guide=path or guide,library=library(branches),edit=edit},style={},constraints={},
    budget={objects=85000,operations=20000000,bytes=64*1024*1024},
    document={unit="cm",bounds=bounds,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=bounds,protected_regions=P.array(),derived=false,
      validity="construction_preserved"},2)
end

local function build(name,branches,edit)
  local q=recipe(name,branches,edit)
  local r=Q.execute(Q.decode(Q.encode(q)),reg,env)
  assert(r.record.status=="complete",P.serialize(r.record.diagnostics))
  local x=r.instance
  local e=x.extensions.decobrush
  assert(#e.contours>=1 and #e.field.seams==2 and e.area.residual<1e-9)
  local plan=V.plan(r.scene,x,r.view,d)
  write(name..".recipe",Q.encode(q))
  write(name..".instance",P.serialize(x))
  write(name..".pdf",V.pdf(plan))
  write(name..".svg",V.svg(plan))
  print(name,#e.contours,e.area.contour_area)
  return r,e
end

for _,name in ipairs({"floral","geometric","branched"}) do build(name,classes[name]) end
local built=build("branched-edit",classes.branched,{{2.065,.827,2.078,.836,false}})

-- Diagnostic baseline: place the identical middle exemplar at every guide interval.
-- The stamp is rigid, with no endpoint selection, deformation or seam correction.
local baseline=P.plain(built.scene)
baseline.operations=P.array()
for i=1,#guide-1 do
  local a,b=guide[i],guide[i+1]
  local length=math.sqrt((b[1]-a[1])^2+(b[2]-a[2])^2)
  local c,s=(b[1]-a[1])/length,(b[2]-a[2])/length
  for _,primitive in ipairs(library(classes.branched)[2].primitives) do
    local commands=P.array()
    for j,p in ipairs(primitive.ring) do commands[j]={j==1 and "M" or "L",p[1],p[2]} end
    commands[#commands+1]={"Z"}
    baseline.operations[#baseline.operations+1]={op="path",semantic_ref=built.instance.id,commands=commands,
      transform={c,s,-s,c,a[1],a[2]},paint={fill={.1,.17,.24}}}
  end
end
local plan=V.plan(baseline,built.instance,built.view,d)
write("fixed-stamp.pdf",V.pdf(plan))
write("fixed-stamp.svg",V.svg(plan))
local failures={}
for _,witness in ipairs({
  {name="length",path={{.4,.55,.6},{1.9,.59,.6},{3.4,.67,.6}},error="no endpoint-preserving"},
  {name="bend",path={{.4,.55,.6},{1.4,.59,.6},{.4,.67,.6}},error="guide bend exceeds chart limit"},
  {name="boundary",path={{.4,.05,.6},{1.4,.09,.6},{2.4,.17,.6},{3.4,.29,.6}},error="deco-chart-outside-document"},
}) do
  local failed=Q.execute(recipe(witness.name,classes.branched,nil,witness.path),reg,env)
  local diagnostics=P.serialize(failed.record.diagnostics)
  assert(failed.record.status~="complete" and diagnostics:find(witness.error,1,true),diagnostics)
  failures[witness.name]=witness.error
end
write("failures.json",P.serialize(failures))
write("receipt.json",P.serialize({source_digest=digest,checks=8,outputs=outputs}))
