local K=require("pattern_celtic")
local function fixture(ps,es,cuts)
 local s={vertices={},edges={},open_sectors=cuts}
 for i,p in ipairs(ps)do s.vertices[i]={id="v"..i,point=p}end
 for i,e in ipairs(es)do s.edges[i]={id="e"..i,from="v"..e[1],to="v"..e[2]}end
 return s
end
local fixtures={
 closed=fixture({{1,1},{4,1},{4,4},{1,4}},{{1,2},{2,3},{3,4},{4,1}}),
 border=fixture({{1,1},{3,1},{5,1},{5,3},{5,5},{3,5},{1,5},{1,3}},{{1,2},{2,3},{3,4},{4,5},{5,6},{6,7},{7,8},{8,1}},{{vertex="v1",edge="e1"}}),
 irregular=fixture({{.8,1.2},{4,.8},{4.6,3.7},{2.2,5},{.7,3.5},{2.45,2.8}},{{1,2},{2,3},{3,4},{4,5},{5,1},{1,6},{2,6},{3,6},{4,6},{5,6}}),
 botanical=fixture({{1,1},{4,1},{2.8,3.9}},{{1,2},{2,3},{3,1}},{{vertex="v3",edge="e2"}}),
}

local P,R,E=require("pattern"),require("pattern_registry"),require("pattern_examples")
local A,H,V=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs")
fixtures.botanical.botanical_port="port/v3/e2/1"
local files={"tools/celticcheck.lua","tools/celtic_oracle.py"}
for n in fs.dir(".")do if n:match("%.lua$")then files[#files+1]=n end end
table.sort(files,P.byte_less)
local source={}
for _,n in ipairs(files)do local f=assert(io.open(n,"rb"));source[#source+1]={path=n,sha256=H.sha256(f:read("*a"):gsub("\r\n","\n"))};f:close()end
local digest=H.sha256(P.serialize(source));local root="build/celtic/"..digest
for _,dir in ipairs{"build","build/celtic",root}do fs.mkdir(dir)end
local outputs={}
local function write(n,data)outputs[n]=A.write(root.."/"..n,data)end
local reg=R.new();local d=K.register(reg)
local frame={id="celtic/world",dimension=2,unit="cm",handedness="right",origin={0,0}}
local crop={0,0,6,6}
local limits={objects=20000,operations=400000,bytes=32*1024*1024}
local function context()return R.context({seed=12,source={revision="working/celtic/"..digest},frame=frame,limits=limits})end
local function build(name,s,scale)
 local spec=P.specification({id="fixture/"..name,definition_ref={id=d.id,version=d.version},seed=12,parameters={smoothing=scale or 1},
  inputs={scaffold=s},constraints={},style={},budget=limits,document={unit="cm",bounds=crop,protected_regions=P.array()}},d)
 return reg:generate(d.id,spec,context())
end
local function paint(name,x,width,box)
 local view=E.view(x,d,box or crop)
 local scene=reg:lower(d.id,x,view,{width=width,halo=.026},context())
 local plan=V.plan(scene,x,view,d)
 write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
 return scene
end
local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1 end
local function reject(f,code)local ok,e=pcall(f);check(not ok and tostring(e):find(code,1,true),tostring(e))end
local summary={}
for _,name in ipairs{"closed","border","irregular","botanical"}do
 local s=fixtures[name];local r,err=build(name,s);assert(r,err and P.serialize(err))
 local x=r.instance;local k=x.structures.strands
 write(name..".instance",P.serialize(x))
 local scene=paint(name,x,.075)
 check(#scene.operations>0,"empty scene")
 summary[name]={components=#k.components,crossings=#k.crossings,ports=#k.ports,operations=#scene.operations}
 local raw=P.plain(x);raw.structures.strands.components[1].encounters[1].branch="invented"
 reject(function()K.validate(raw)end,"knot-strand-record-mismatch")
 if name=="botanical"then
  check(x.extensions.celtic.attachment.port==s.botanical_port,"attachment identity")
  local attached=0;for _,p in ipairs(scene.operations)do if p.semantic_ref==s.botanical_port then attached=attached+1 end end;check(attached>1,"attachment actual paint")
  raw=P.plain(x);raw.extensions.celtic.attachment.root={0,0}
  reject(function()K.validate(raw)end,"knot-attachment-mismatch")
 end
 if name=="closed"then
  local wide=paint("closed-narrow",x,.062)
  check(#wide.operations==#scene.operations,"width changed operation count")
  for j,p in ipairs(wide.operations)do check(p.semantic_ref==scene.operations[j].semantic_ref,"width changed strand identity")end
  local clipped=paint("closed-cropped",x,.075,{1.7,1.7,3.4,3.4})
  check(#clipped.operations==#scene.operations and #k.ports==0,"crop generated topology ends")
  reject(function()paint("impossible",x,2)end,"knot-ribbon-clearance")
 end
end
local impossible=P.plain(fixtures.closed);impossible.above={e1="L",e2="L"}
local pass,err=build("impossible",impossible)
if pass then impossible.above.e2="R";pass,err=build("impossible",impossible)end
check(not pass and P.serialize(err):find("knot-incompatible-alternation",1,true),"conflicting crossing pins accepted")
local crossing=fixture({{0,0},{1,1},{1,0},{0,1}},{{1,2},{3,4}})
reject(function()K.topology(crossing)end,"knot-nonplanar")
local witness="acute-triangle"
local acute=fixture({{0,0},{4,0},{.1,.8}},{{1,2},{2,3},{1,3}})
local acute_topology=K.topology(acute)
check(#K.smooth(acute_topology,.4)>0,"safe smoothing rejected")
reject(function()K.smooth(acute_topology,3)end,"knot-smoothing-collision")
local report={stage="10",source_digest=digest,source=source,checks=checks,fixtures=summary,
 runtime=_VERSION,host=PATTERN_TEST_HOST or "texlua",outputs=outputs,smoothing_collision=witness}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("celticcheck: "..checks.." checks; four semantic/rendered fixtures; source "..digest)






