local P,R,D,L,Q,E=require("pattern"),require("pattern_registry"),require("pattern_document"),require("pattern_planner"),require("pattern_recipe"),require("pattern_examples")
local F=require("pattern_penrose")
local A,H,V=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs")
local names={"tools/penrosecheck.lua","tools/penrose_oracle.py"}
for n in fs.dir(".") do if n:match("%.lua$") then names[#names+1]=n end end
table.sort(names,P.byte_less)
local source,bytes={},{}
for _,n in ipairs(names) do
  local f=assert(io.open(n,"rb"));bytes[n]=f:read("*a"):gsub("\r\n","\n");f:close()
  source[#source+1]={path=n,sha256=H.sha256(bytes[n])}
end
local digest=H.sha256(P.serialize(source))
local root="build/penrose/"..digest
for _,d in ipairs{"build","build/penrose",root} do fs.mkdir(d) end
local outputs={}
local function write(n,data) outputs[n]=A.write(root.."/"..n,data) end
local reg=R.new();local definition=F.register(reg)
local frame={id="penrose/world",dimension=2,unit="cm",handedness="right",origin={.125,-.25}}
local limits={objects=35000,operations=400000,bytes=32*1024*1024}
local host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")
local function ctx()
  return R.context({seed=14,frame=frame,limits=limits,source={revision="working/penrose/"..digest}})
end
local function spec(n,box,phase)
  return P.specification({id="penrose/"..n,definition_ref={id=definition.id,version=definition.version},
    seed=14,parameters={phase=phase,edge_length=.45},inputs={},constraints={},style={},budget=limits,
    document={unit="cm",bounds=box,protected_regions=P.array()}},definition)
end
local function generate(s)
  local r,e=reg:generate(definition.id,s,ctx())
  assert(r,e and P.serialize(e))
  return r.instance
end
local function draw(n,x,view,scene)
  local plan=V.plan(scene,x,view,definition)
  write(n..".pdf",V.pdf(plan));write(n..".svg",V.svg(plan))
end
local function render(n,x,box,display)
  local v=E.view(x,definition,box)
  local scene=reg:lower(definition.id,x,v,{display=display or "clean"},ctx())
  draw(n,x,v,scene)
  return #scene.operations
end
local checks=0
local function check(v,msg) assert(v,msg);checks=checks+1 end
local function reject(f,reason)
  local ok,e=pcall(f)
  check(not ok and tostring(e):find(reason,1,true),tostring(e))
end
local function index(list)
  local out={}
  for _,v in ipairs(list) do out[v.id]=v end
  return out
end
local function eq(a,b) return P.serialize(a)==P.serialize(b) end
local queries={small={-2,-1.5,2.5,1.7},medium={-3,-2.3,3,2.4},large={-4.1,-3.3,4.4,3.6},
  offset={-.8,-2.1,3.5,2.2},indigo={-2,-1.5,2.5,1.7}}
local instances,specs={},{}
for _,n in ipairs{"small","medium","large","offset","indigo"} do
  specs[n]=spec(n,queries[n],n=="indigo" and "indigo" or "amber")
  instances[n]=generate(specs[n])
  write(n..".instance",P.serialize(instances[n]))
end
local small,large,other=instances.small,instances.large,instances.offset
local a,m,b,c=index(small.structures.tiling.cells),index(instances.medium.structures.tiling.cells),
  index(large.structures.tiling.cells),index(other.structures.tiling.cells)
local shared=0
for id,v in pairs(a) do
  assert(eq(v,m[id]) and eq(v,b[id]),"query expansion changed a lifted tile")
  if c[id] then assert(eq(v,c[id]),"shared tile changed");shared=shared+1 end
end
for id,v in pairs(m) do assert(eq(v,b[id]),"second expansion changed a lifted tile") end
check(#small.structures.tiling.cells<#instances.medium.structures.tiling.cells
  and #instances.medium.structures.tiling.cells<#large.structures.tiling.cells and shared>0,"expansion counts")
local global=index(large.structures.tiling.edges)
for _,e in ipairs(small.structures.tiling.edges) do
  assert(eq(e.matching,global[e.id].matching) and eq(e.global_cells,global[e.id].global_cells),"world edge changed")
end
check(small.extensions.penrose.certificate.query_cuts>0,"missing query cuts")
check(small.extensions.penrose.certificate.selected_counts.thin>0
  and small.extensions.penrose.certificate.selected_counts.thick>0,"missing prototile")
local indigo=index(instances.indigo.structures.tiling.cells)
local disjoint=true;for id in pairs(a)do if indigo[id] then disjoint=false;break end end
check(disjoint,
  "phase did not namespace identity")
local crops={clean={-1.9,-1.4,1.85,1.35},offset={-.5,-1.6,3.25,1.65},
  diagnostic={-1.9,-1.4,1.85,1.35},common={-.55,-.95,1.95,.8},alternate={-1.9,-1.4,1.85,1.35}}
local n=render("clean",small,crops.clean)
check(render("diagnostic",small,crops.diagnostic,"matching")>n,"matching display produced no arrow marks")
render("offset",other,crops.offset)
render("alternate",instances.indigo,crops.alternate)
render("common-a",small,crops.common);render("common-b",other,crops.common)
check(outputs["common-a.pdf"]==outputs["common-b.pdf"] and outputs["common-a.svg"]==outputs["common-b.svg"],
  "same physical window changed vector bytes")
reject(function()F.phase({0,0,0,0,0},1)end,"penrose-phase-not-certified-regular")
reject(function()F.phase({1,0,0,0,0},7)end,"penrose-phase-must-sum-zero")
reject(function()generate(spec("oversize",{-25,-2,25,2},"amber"))end,"penrose-query-span")
reject(function()render("out",small,{-3,-1,2,1})end,"penrose-view-outside-certified-query")
for _,mutate in ipairs{
  function(v)v.structures.tiling.vertices[1].lift[1]=v.structures.tiling.vertices[1].lift[1]+1 end,
  function(v)v.structures.tiling.edges[1].matching.class="fabricated" end,
  function(v)v.structures.tiling.cells[1].isometry.rotation_degrees=17 end,
} do
  local broken=P.plain(small);mutate(broken)
  reject(function()F.validate(broken)end,"penrose-lift-or-matching-reconstruction")
end
local reflected=P.plain(E.view(small,definition,crops.clean));reflected.transform={-1,0,0,1,0,0}
reject(function()P.view(reflected,small,definition)end,"reflection")
local function page(id,number,x)
  return {id=id,number=number,size={2.5,3.2},origin={x,-1.6},trim={0,0,2.5,3.2},bleed={0,0,0,0},
    margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions=P.array()}
end
local pages={page("verso",2,-2.3),page("recto",3,.2)}
local doc=D.new({id="penrose-spread",unit="cm",frame={id=frame.id,origin=frame.origin},twoside=true,pages=pages,
  spreads={{id="center",left="verso",right="recto",gutter=0}}})
local profile=L.profile(definition,{mode="view_only",construction_scale=.45})
local plans={}
for i,p in ipairs(pages) do
  local c0=ctx()
  local planned,e=L.view(large,definition,doc,p.id,profile,{},c0);assert(planned,e and P.serialize(e))
  local d0,err=L.lower(reg,definition.id,large,definition,planned,{display="matching"},c0);assert(d0,err and P.serialize(err))
  draw(i==1 and "spread-left" or "spread-right",large,d0.view,d0.scene)
  plans[i]=P.plain(d0.view)
end
check(plans[1].extensions.document.topology_unchanged and plans[2].extensions.document.topology_unchanged,"spread changed construction")
write("spread-views.json",P.serialize(plans))
local recipe=assert(L.recipe(definition,specs.large,doc,"verso",profile,{},{ }))
local env=Q.environment({revision="working/penrose/"..digest,files={construction=bytes,style={},view={},renderer={}}},
  {lua=_VERSION,host=host},{id=V.VERSION,version="1"})
local build=Q.execute(Q.decode(Q.encode(recipe)),reg,env)
check(build.record.status=="complete",P.serialize(build.record))
check(build.bytes.instance==P.serialize(large),"recipe regenerated a different anchored patch")
check(build.record.extensions.construction.method==F.VERSION and #build.record.extensions.construction.phase.regularity==10,
  "build record missing exact source and phase witness")
write("spread.recipe",Q.encode(recipe))
local report={stage="14",source_digest=digest,source=source,checks=checks,outputs=outputs,shared=shared,crops=crops,
  runtime=_VERSION,host=host,build_record=P.plain(build.record)}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("penrosecheck: "..checks.." checks; "..shared.." shared rhombi; source "..digest)
