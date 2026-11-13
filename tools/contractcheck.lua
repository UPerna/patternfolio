-- Executable contracts and adversarial semantic fixtures. Run from repository root.
local P,R,E=require("pattern"),require("pattern_registry"),require("pattern_examples")
local count=0
local function check(ok,message) assert(ok,message);count=count+1 end
local function rejects(fn,needle)
  local ok,err=pcall(fn);check(not ok and (not needle or tostring(err):find(needle,1,true)),"expected rejection: "..tostring(err))
end
local function context(extra)
  local t={seed=7,source={revision="contract-fixture"}};for k,v in pairs(extra or {}) do t[k]=v end
  return R.context(t)
end
local registry,defs=E.registry();local examples={}
for _,name in ipairs({"floral","graph","tiling"}) do
  local d,c=defs[name],context();local spec=E.specification(d)
  local result,err=registry:generate(d.id,spec,c);check(result~=nil,err and err.diagnostics[1])
  local x=result.instance;local v=E.view(x,d);local scene=registry:lower(d.id,x,v,{},c)
  for _,item in ipairs({{d,"definition"},{spec,"specification",d},{x,"instance",d},{v,"view",x,d},{scene,"scene",x,v,d}}) do
    local bytes=P.serialize(item[1]);local decoded=P.deserialize(bytes,item[2],table.unpack(item,3))
    check(P.serialize(decoded)==bytes,"stable serialized round trip: "..name.."/"..item[2])
  end
  rejects(function() x.frame.origin[1]=19 end,"immutable")
  local copy=P.plain(x);copy.frame.origin[1]=19;check(x.frame.origin[1]==0,"owned snapshot")
  local before=P.serialize(x);local crop=E.view(x,d,{0.2,0.2,1.8,0.8});local s=registry:lower(d.id,x,crop,{},c)
  check(P.serialize(x)==before and s.clip.bounds[1]==0.2,"crop preserves semantic instance")
  examples[name]={instance=x,scene=scene,definition=d}
end
check(#examples.floral.scene.resources[1].variants.scene.content>1000,"real backend-neutral floral geometry")
local gx=examples.graph.instance;local gv=E.view(gx,defs.graph)
local styled=registry:lower(defs.graph.id,gx,gv,{stroke={1,0,0},stroke_width=0.1},context())
check(styled.operations[1].paint.stroke[1]==1 and P.serialize(gx)==P.serialize(examples.graph.instance),"independent style")
rejects(function() registry:lower(defs.graph.id,gx,gv,{pretend=1},context()) end,"unsupported")
local tx=examples.tiling.instance
local function corrupt_instance(change,kind)
  local d=defs[kind or "tiling"];local x=P.plain(examples[kind or "tiling"].instance);change(x)
  rejects(function() P.instance(x,d) end)
end
corrupt_instance(function(x) x.structures.tiling.cells[1].chirality=-1 end)
corrupt_instance(function(x) x.structures.tiling.edges[1].owner="absent" end)
corrupt_instance(function(x) x.structures.tiling.edges[1].role="decoration" end)
corrupt_instance(function(x) x.structures.tiling.cells[2].boundary[4].reversed=false end)
corrupt_instance(function(x) x.structures.tiling.hierarchy[1].children[3]=x.structures.tiling.hierarchy[1].id end)
corrupt_instance(function(x) x.structures.graph.edges[1].to="missing" end,"graph")
corrupt_instance(function(x) x.frame.origin[1]=0/0 end,"graph")
for _,m in ipairs({{2,0,0,1,0,0},{1,0,0.3,1,0,0},{-1,0,0,1,0,0}}) do
  local v=P.plain(E.view(tx,defs.tiling));v.transform=m
  rejects(function() P.view(v,tx,defs.tiling) end)
  v.derived=true;v.validity="visualization_only";check(P.view(v,tx,defs.tiling).derived,"explicit derived distortion")
end
local invalid=P.plain(defs.graph);invalid.schema_version=2
rejects(function() P.definition(invalid) end,"migration")
invalid=P.plain(E.specification(defs.graph));invalid.parameters.unknown=1
rejects(function() P.specification(invalid,defs.graph) end,"unsupported control")
rejects(function() P.snapshot({value=math.mininteger}) end,"portable")
local cyc={};cyc.self=cyc;rejects(function() P.snapshot(cyc) end,"cyclic")
local sc=P.plain(examples.graph.scene);sc.clip.bounds[1]=0.1
rejects(function() P.scene(sc,gx,gv,defs.graph) end,"survive lowering")
sc=P.plain(examples.graph.scene);sc.operations[1].semantic_ref="missing"
rejects(function() P.scene(sc,gx,gv,defs.graph) end,"semantic source")
local function fixture(tag,structure,dimension)
  local d=P.plain(defs.graph);d.id="fixture/"..tag;d.capabilities={tag};d=P.definition(d)
  local x=P.plain(gx);x.id=d.id.."/instance";x.definition_ref={id=d.id,version=d.version};x.provenance.generator=d.id
  x.structures={[tag]=structure};x.frame.dimension=dimension or 2;x.frame.origin=dimension==3 and {0,0,0} or {0,0}
  return P.instance(x,d),d
end
local text,td=fixture("text",{runs={{id="run/a",text="Á α",direction="ltr"},{id="run/b",text="B",direction="ltr"}},reading_order={"run/b","run/a"}})
check(P.deserialize(P.serialize(text),"instance",td).structures.text.reading_order[1]=="run/b","reading order survives serialization")
invalid=P.plain(text);invalid.structures.text.reading_order={"run/a","foreign"}
rejects(function() P.instance(invalid,td) end,"missing text run")
local strands,sd=fixture("strands",{ports=P.array(),components={{id="strand",closed=true,alternating=true,endpoints=P.array(),encounters={{crossing="cross",role="over"},{crossing="cross",role="under"}}}},crossings={{id="cross",over="strand",under="strand",self_crossing=true,point={0,0}}}})
check(strands.structures.strands.crossings[1].self_crossing,"self crossing identity")
invalid=P.plain(strands);invalid.structures.strands.components[1].encounters[2].role="over"
rejects(function() P.instance(invalid,sd) end,"duplicate crossing role")
local curves,cd=fixture("curve3d",{vertices={{id="v0",point={0,0,0}},{id="v1",point={1,1,1}}},curves={{id="curve",from="v0",to="v1"}}},3)
rejects(function() E.view(curves,cd) end,"projection")
local cv={id="projected",instance_ref=curves.id,unit="cm",transform={1,0,0,1,0,0},crop={0,0,8,8},protected_regions=P.array(),derived=true,validity="visualization_only",projection={matrix={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1},depth_policy="all_curves"}}
check(P.view(cv,curves,cd).derived,"explicit 3D projection contract")
local field=fixture("field",{representation="samples",domain={bounds={0,0,1,1}},samples={{id="sample",point={0.5,0.5},vector={1,0},density=1}}})
check(field.structures.field.samples[1].density==1,"field capability")
local result,err=registry:generate(defs.graph.id,E.specification(defs.graph),context({limits={objects=4,operations=10,bytes=10000}}))
check(not result and err.code=="budget_exhausted","budget failure is not accepted output")
result,err=registry:generate(defs.graph.id,E.specification(defs.graph),context({cancelled=function() return true end}))
check(not result and err.status=="cancelled","cancellation receipt")
rejects(function() context():stream("geometry","id") end,"not configured")
local hash=require("pattern_hash").sha256
local record={id="build/test",status="complete",source={revision="fixture",digest=hash("fixture source")},runtime={name="Lua",version=_VERSION},seed=7,inputs={{kind="fixture",sha256=hash("fixture input")}},dependencies={},lineage=P.array(),validation={status="passed",checks={"contractcheck"}},outputs={{path="memory:scene",kind="scene",sha256=hash("fixture scene")}},diagnostics=P.array(),budgets=context():receipt()}
local build=P.build_record(record);check(P.serialize(P.deserialize(P.serialize(build),"build_record"))==P.serialize(build),"build record roundtrip")
record.validation.checks=P.array();rejects(function() P.build_record(record) end,"actual validation")
print("contractcheck: "..count.." checks passed; actual floral + graph + tiling examples; semantic-only text/strands/3D/field fixtures")
