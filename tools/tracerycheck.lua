local P,R,D,L,Q,E=require("pattern"),require("pattern_registry"),require("pattern_document"),
  require("pattern_planner"),require("pattern_recipe"),require("pattern_examples")
local F,V,H,A=require("pattern_tracery"),require("pattern_render"),
  require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local data=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name]=data;hashes[name]=H.sha256(data)
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
read("tools/tracerycheck.lua");read("tools/tracery_oracle.py")
local digest=H.value("tracery/source",hashes)
local root="build/tracery/"..digest
for _,path in ipairs{"build","build/tracery",root} do fs.mkdir(path) end
local outputs={}
local function write(name,bytes) outputs[name]=A.write(root.."/"..name,bytes) end
local checks=0
local function check(ok,reason) assert(ok,reason);checks=checks+1 end
local reg=R.new()
local d=F.register(reg)
local frame={id="tracery/world",unit="cm",origin={0,0},handedness="right",dimension=2}
local limits={objects=20000,operations=400000,bytes=64*1024*1024}
local function context()
  return R.context({seed=19,frame=frame,source={revision="working/tracery/"..digest},limits=limits})
end
local function spec(id,parameters,box,style)
  return {id="tracery/"..id,definition_ref={id=d.id,version=d.version},seed=19,parameters=parameters,
    inputs={},constraints={},style=style or {},budget=limits,
    document={unit="cm",bounds=box,protected_regions=P.array()}}
end
local function make(name,parameters,box)
  local result,e=reg:generate(d.id,spec(name,parameters,box),context())
  assert(result,e and P.serialize(e))
  return result.instance
end
local function render(name,x,box,style,save_scene)
  local v=E.view(x,d,box)
  local scene=reg:lower(d.id,x,v,style or {},context())
  local plan=V.plan(scene,x,v,d)
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
  if save_scene then write(name..".scene",P.serialize(scene)) end
end
local fixtures={
  {"prototype",{profile="prototype",width=8,jamb=5,excess=1},{-.3,-.3,8.3,12.3}},
  {"rosette",{profile="rosette",width=8,jamb=4.5,excess=1,drop=.65,foils=5},{-.3,-.3,8.3,11.8}},
  {"narrow",{profile="rosette",width=4.4,jamb=4.2,excess=.62,drop=.32,foils=4},{-.3,-.3,4.7,7.3}},
  {"rose",{profile="rose",width=8,foils=6,recursion=1},{-.3,-.3,8.3,8.3}},
}
local instances={}
for _,f in ipairs(fixtures) do
  local name,p,box=table.unpack(f)
  local x=make(name,p,box)
  instances[name]=x
  local g=x.extensions.tracery.grammar
  check(#x.structures.graph.edges>=11 and g.profile==p.profile,"incomplete construction graph")
  write(name..".instance",P.serialize(x))
  render(name,x,box,{profile="stone"},true)
  render(name.."-diagnostic",x,box,{profile="diagnostic"},true)
end
local rose=instances.rose
check(#rose.extensions.tracery.grammar.foils==7,"recursive foil rings did not construct")
local rosette=instances.rosette
local grammar=rosette.extensions.tracery.grammar
check(#grammar.contacts==4 and #grammar.arches==3,"crown contacts or paired bays missing")
local edited=P.plain(fixtures[2][2])
edited.drop=1.05
local changed=make("edited",edited,fixtures[2][3])
local g=changed.extensions.tracery.grammar
check(g.arches[1].apex[2]==grammar.arches[1].apex[2] and g.arches[2].spring<grammar.arches[2].spring
  and g.rings[1].center[2]<grammar.rings[1].center[2],"drop edit did not update its dependents")
write("edited.instance",P.serialize(changed))
render("edited",changed,fixtures[2][3],{profile="ink"})
local contact
for _,vertex in ipairs(rosette.structures.graph.vertices) do
  if vertex.id==grammar.contacts[3].id then contact=vertex.point;break end
end
assert(contact,"missing lower tangent junction")
local joins={contact[1]-1,contact[2]-1,contact[1]+1,contact[2]+1}
render("join-detail",rosette,joins,{profile="stone"})
render("join-detail-diagnostic",rosette,joins,{profile="diagnostic"})

local invalids={
  {"excess",{profile="prototype",width=8,jamb=5,excess=.5},"minimum"},
  {"drop",{profile="prototype",width=8,jamb=3,excess=1,drop=3},"tracery-collapsed-subwindow"},
  {"branch",{profile="rosette",width=2,jamb=10,excess=1.8,drop=8},"tracery-rosette-unbracketed"},
  {"recursion",{profile="rose",width=2,foils=9,recursion=2},"tracery-foil-radius-limit"},
  {"irrelevant",{profile="rose",width=8,excess=1},"tracery-arch-parameters-on-rose"},
}
for _,item in ipairs(invalids) do
  local success,value,reason=pcall(reg.generate,reg,d.id,spec(item[1],item[2],fixtures[1][3]),context())
  local diagnostic=success and reason and P.serialize(reason) or tostring(value)
  check(not value and diagnostic:find(item[3],1,true) or not success and diagnostic:find(item[3],1,true),
    "invalid case accepted or wrong diagnostic: "..item[1].." "..diagnostic)
end
local ok,err=pcall(reg.lower,reg,d.id,rose,E.view(rose,d,fixtures[4][3]),{band_cm=.6},context())
check(not ok and tostring(err):find("tracery-profile-collapsed-foil",1,true),"collapsed profile accepted")
local corrupt=P.plain(rosette)
corrupt.extensions.tracery.grammar.contacts[1].radius=corrupt.extensions.tracery.grammar.contacts[1].radius+.01
check(not pcall(F.validate,corrupt),"forged contact record accepted")

local box=fixtures[2][3]
local w,h=box[3]-box[1],box[4]-box[2]
local doc=D.new({id="tracery-document",unit="cm",frame={id=frame.id,origin=frame.origin},twoside=false,spreads=P.array(),
  pages={{id="window",number=1,size={w,h},origin={box[1],box[2]},trim={0,0,w,h},
    bleed={0,0,0,0},margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions=P.array()}}})
local env=Q.environment({revision="working/tracery/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=V.VERSION,version="1"})
local profile=L.profile(d,{mode="view_only",construction_scale=8})
local s=spec("saved",fixtures[2][2],box,{profile="stone"})
local recipe=assert(L.recipe(d,s,doc,"window",profile,{},{}))
local saved=Q.encode(recipe)
local first=Q.execute(Q.decode(saved),reg,env)
assert(first.record.status=="complete",P.serialize(first.record.diagnostics))
s.style={profile="ink",band_cm=.135}
local second=Q.execute(assert(L.recipe(d,s,doc,"window",profile,{},{})),reg,env)
assert(second.record.status=="complete",P.serialize(second.record.diagnostics))
check(first.bytes.instance==P.serialize(rosette) and second.bytes.instance==first.bytes.instance,
  "appearance edit changed construction")
check(first.keys.structure==second.keys.structure and first.keys.style~=second.keys.style
  and first.bytes.scene~=second.bytes.scene,"appearance and construction cache scopes mixed")
check(Q.encode(Q.decode(saved))==saved and first.planning.source_digest==H.sha256(first.bytes.instance),
  "document recipe did not preserve the graph")
write("rosette.recipe",saved)
A.write(root.."/receipt.json",P.serialize({stage="19",source_digest=digest,checks=checks,outputs=outputs}))
print("Gothic tracery: "..checks.." checks; analytic windows and recursive rose")
