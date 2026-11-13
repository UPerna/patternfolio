local P,R,D,L,Q,E=require("pattern"),require("pattern_registry"),require("pattern_document"),
  require("pattern_planner"),require("pattern_recipe"),require("pattern_examples")
local F,V,H,A=require("pattern_ammann_beenker"),require("pattern_render"),
  require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local data=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name]=data;hashes[name]=H.sha256(data)
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
read("tools/beenkercheck.lua")
read("tools/beenker_oracle.py")
local digest=H.value("beenker/source",hashes)
local root="build/beenker/"..digest
for _,path in ipairs{"build","build/beenker",root} do fs.mkdir(path) end
local output={}
local function write(name,data) output[name]=A.write(root.."/"..name,data) end
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local registry=R.new()
local d=F.register(registry)
local frame={id="beenker/world",unit="cm",dimension=2,origin={.25,-.25},handedness="right"}
local limits={objects=25000,operations=400000,bytes=64*1024*1024}
local function context()
  return R.context({seed=17,source={revision="working/beenker/"..digest},frame=frame,limits=limits})
end
local function spec(name,box,phase)
  return P.specification({id="fixture/"..name,definition_ref={id=d.id,version=d.version},seed=17,
    parameters={phase=phase,edge_length=.5},constraints={},inputs={},style={},budget=limits,
    document={unit="cm",bounds=box,protected_regions=P.array()}},d)
end
local function build(name,box,phase)
  local s=spec(name,box,phase)
  local result,problem=registry:generate(d.id,s,context())
  assert(result,problem and P.serialize(problem))
  check(result.validation.construction.method==F.VERSION,"route was not exercised")
  write(name..".instance",P.serialize(result.instance))
  return result.instance,s
end
local function export(name,plan)
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
end
local function view(x,box,style)
  local v=E.view(x,d,box)
  local scene=registry:lower(d.id,x,v,style or {},context())
  return V.plan(scene,x,v,d)
end
local small_box,offset_box,wide_box={-2.25,-2.25,2.75,1.75},{.25,-1.75,3.75,2.25},{-4.25,-3.25,4.75,3.75}
local center_box={-2.75,-3.25,3.25,2.75}
local singular_box={-1.75,-2.25,2.25,1.75}
local small,saved=build("offset",small_box,"offset")
local offset=build("noncentral",offset_box,"offset")
local wide=build("extended",wide_box,"offset")
local centered=build("centered",center_box,"centered")
local plus=build("zero-plus",singular_box,"zero-plus")
local minus=build("zero-minus",singular_box,"zero-minus")
export("offset",view(small,small_box))
export("noncentral",view(offset,offset_box))
export("extended",view(wide,wide_box))
export("centered",view(centered,center_box))
export("zero-plus",view(plus,singular_box,{display="diagnostic"}))
export("zero-minus",view(minus,singular_box,{display="diagnostic"}))
local function index(items)
  local by_id={}
  for _,item in ipairs(items) do by_id[item.id]=item end
  return by_id
end
local shared=0
local global=index(wide.structures.tiling.cells)
local wide_edges=index(wide.structures.tiling.edges)
for _,cell in ipairs(small.structures.tiling.cells) do
  local other=assert(global[cell.id],"extended query lost a tile")
  assert(P.serialize(cell)==P.serialize(other),"extended query changed a lifted tile")
  shared=shared+1
end
for _,edge in ipairs(small.structures.tiling.edges) do
  local other=assert(wide_edges[edge.id],"extended query lost an edge")
  assert(other.global_owner==edge.global_owner and P.serialize(other.global_cells)==P.serialize(edge.global_cells),
    "extended query reassigned global incidence")
end
check(shared>=100,"overlap did not exercise enough tiles")
local common={.25,-1.25,2.25,1.25}
local a,b=view(small,common),view(offset,common)
check(V.pdf(a)==V.pdf(b) and V.svg(a)==V.svg(b),"same physical crop is not byte-identical")
export("common-a",a);export("common-b",b)
for _,x in ipairs{plus,minus} do
  local t=x.extensions.beenker.certificate.ties
  check(t.count>0 and t.positive>0 and t.negative>0 and t.count==t.positive+t.negative,"ties not exercised")
end
check(V.svg(view(plus,singular_box))~=V.svg(view(minus,singular_box)),"opposite coherent limits collapsed")
local corrupt=P.plain(small)
corrupt.structures.tiling.vertices[1].internal[1][2]=corrupt.structures.tiling.vertices[1].internal[1][2]+1
check(not pcall(F.validate,corrupt),"forged internal lift accepted")
local bad,reason=registry:generate(d.id,spec("bad",{40,40,41,41},"offset"),context())
check(not bad and P.serialize(reason):find("beenker-query-horizon",1,true),"unbounded query accepted")
check(not pcall(view,small,wide_box),"uncertified view accepted")

local function page(id,number,x)
  return {id=id,number=number,size={3.5,3.6},origin={x,-1.8},trim={0,0,3.5,3.6},
    bleed={0,0,0,0},margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions=P.array()}
end
local pages={page("verso",2,-3),page("recto",3,.7)}
local document=D.new({id="beenker-spread",unit="cm",frame={id=frame.id,origin=frame.origin},twoside=true,
  pages=pages,spreads={{id="spread",left="verso",right="recto",gutter=.2}}})
local profile=L.profile(d,{mode="fixed_frame",construction_scale=.5,maximum_tile_diameter=1})
local recipe=assert(L.recipe(d,saved,document,"verso",profile,{},{}))
local env=Q.environment({revision="working/beenker/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=V.VERSION,version="1"})
local encoded=Q.encode(recipe)
local result=Q.execute(Q.decode(encoded),registry,env)
assert(result.record.status=="complete",P.serialize(result.record.diagnostics))
check(result.record.extensions.construction.method==F.VERSION and Q.encode(Q.decode(encoded))==encoded,
  "document recipe did not retain construction provenance")
local x=result.instance
local right=assert(L.view(x,d,document,"recto",profile,{},context()))
local lowered=assert(L.lower(registry,d.id,x,d,right,{},context()))
check(right.source_digest==H.sha256(result.bytes.instance) and result.planning.source_digest==right.source_digest,
  "spread changed the source patch")
local spread={V.plan(result.scene,x,result.view,d),V.plan(lowered.scene,x,lowered.view,d)}
write("spread.pdf",V.pdf_document(spread))
write("spread-1.svg",V.svg(spread[1]));write("spread-2.svg",V.svg(spread[2]))
write("spread.recipe",encoded)
write("spread.instance",result.bytes.instance)
write("spread-views.json",P.serialize({result.view,lowered.view}))
A.write(root.."/receipt.json",P.serialize({stage="17",source_digest=digest,checks=checks,outputs=output,shared=shared}))
print("Ammann-Beenker: "..checks.." checks; "..shared.." shared tiles")
