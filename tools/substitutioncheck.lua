local P,R,D,L,Q,E=require("pattern"),require("pattern_registry"),require("pattern_document"),require("pattern_planner"),require("pattern_recipe"),require("pattern_examples")
local F=require("pattern_aperiodic")
local A,H,V=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs")
local files={"tools/substitutioncheck.lua","tools/substitution_oracle.py"}
for name in fs.dir(".") do if name:match("%.lua$") then files[#files+1]=name end end
table.sort(files,P.byte_less)
local sources,bytes={},{}
for _,n in ipairs(files) do
  local f=assert(io.open(n,"rb"))
  bytes[n]=f:read("*a"):gsub("\r\n","\n");f:close()
  sources[#sources+1]={path=n,sha256=H.sha256(bytes[n])}
end
local digest=H.sha256(P.serialize(sources))
local root="build/substitution/"..digest
for _,d in ipairs{"build","build/substitution",root} do fs.mkdir(d) end
local outputs={}
local function write(n,data) outputs[n]=A.write(root.."/"..n,data) end
local registry=R.new()
local definition=F.register(registry)
local origin={.5,-.25};local step=.25
local frame={id="chair/world",dimension=2,unit="cm",handedness="right",origin=origin}
local limits={objects=22000,operations=400000,bytes=32*1024*1024}
local host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")
local function context(planning)
  return R.context({seed=13,frame=frame,limits=limits,planning=planning,source={revision="working/chair/"..digest}})
end
local function world(box)
  local out={}
  for i,x in ipairs(box) do out[i]=origin[(i-1)%2+1]+x*step end
  return out
end
local function spec(name,box,extra)
  local params={root_depth=4,leaf_step=step,halo=3}
  for k,v in pairs(extra or {}) do params[k]=v end
  return P.specification({id="chair/"..name,definition_ref={id=definition.id,version=definition.version},seed=13,
    parameters=params,inputs={},constraints={},style={},budget=limits,
    document={unit="cm",bounds=world(box),protected_regions=P.array()}},definition)
end
local function generate(s)
  local result,err=registry:generate(definition.id,s,context())
  assert(result,err and P.serialize(err))
  return result.instance
end
local function render(name,x,box)
  local view=E.view(x,definition,world(box))
  local scene=registry:lower(definition.id,x,view,{},context())
  local plan=V.plan(scene,x,view,definition)
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
end
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function expect_failure(f,needle)
  local ok,err=pcall(f)
  check(not ok and tostring(err):find(needle,1,true),tostring(err))
end
local function index(values)
  local out={}
  for _,v in ipairs(values) do out[v.id]=v end
  return out
end
local function eq(a,b) return P.serialize(a)==P.serialize(b) end
local queries={root={0,0,32,32},a={3,3,14,12},b={8,5,19,14},expanded={2,2,22,15},common={9,6,13,11}}
local x={}
for _,name in ipairs{"root","a","b","expanded"} do
  x[name]=generate(spec(name,queries[name],name=="root" and {whole_root=true} or nil))
  write(name..".instance",P.serialize(x[name]))
end
check(#x.root.structures.tiling.cells==256,"wrong root leaf count")
check(x.root.extensions.substitution.certificate.root_unit_square_count==768,"wrong exact coverage")
check(#x.root.structures.tiling.hierarchy==85,"wrong full hierarchy")
local global=index(x.root.structures.tiling.cells)
local root_edges=index(x.root.structures.tiling.edges)
local expanded=index(x.expanded.structures.tiling.cells)
local a,b=index(x.a.structures.tiling.cells),index(x.b.structures.tiling.cells)
local shared=0
for id,cell in pairs(a) do
  assert(eq(cell,global[id]) and eq(cell,expanded[id]),"expansion renamed or changed a leaf")
  if b[id] then assert(eq(cell,b[id]),"overlap changed a leaf");shared=shared+1 end
end
check(shared>0 and #x.expanded.structures.tiling.cells>#x.a.structures.tiling.cells,"insufficient overlap")
local cut=0
for _,edge in ipairs(x.a.structures.tiling.edges) do
  assert(eq(edge.global_cells,root_edges[edge.id].global_cells) and edge.global_owner==root_edges[edge.id].global_owner,
    "query cut changed the world seam")
  if edge.boundary_reason=="query_cut" then cut=cut+1 end
end
check(cut>0,"query has no classified cuts")
render("root",x.root,queries.root)
render("a",x.a,queries.a)
render("common-a",x.a,queries.common)
render("common-b",x.b,queries.common)
check(outputs["common-a.pdf"]==outputs["common-b.pdf"] and outputs["common-a.svg"]==outputs["common-b.svg"],
  "same world viewport did not replay exactly")
for _,case in ipairs{
  {function(t)t.structures.tiling.cells[1].exact_transform.chirality=-1 end,"aperiodic-reflection-or-isometry"},
  {function(t)t.structures.tiling.cells[2].squares=P.plain(t.structures.tiling.cells[1].squares)end,"aperiodic-duplicate-or-overlap"},
  {function(t)t.structures.tiling.vertices[1].point[1]=t.structures.tiling.vertices[1].point[1]+.02 end,"aperiodic-seam-coordinate"},
  {function(t)t.structures.tiling.cells[1].parent="invented" end,"aperiodic-parent-child-certificate"},
} do
  local data=P.plain(x.a);case[1](data)
  expect_failure(function()F.validate(data)end,case[2])
end
expect_failure(function()generate(spec("out",{15,15,18,18}))end,"aperiodic-outside-finite-horizon")
expect_failure(function()render("out",x.a,{1,1,20,16})end,"aperiodic-view-outside-certified-query")
for _,route in ipairs{"projection_multigrid","bounded_constraint"} do
  expect_failure(function()generate(spec("unsupported",queries.a,{route=route}))end,"aperiodic-route-unimplemented")
end
local source_spec=spec("a",queries.a)
local cb=world(queries.common)
local w,h=cb[3]-cb[1],cb[4]-cb[2]
local page={id="window",number=1,size={w,h},origin={cb[1],cb[2]},trim={0,0,w,h},bleed={0,0,0,0},
  margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions=P.array()}
local doc=D.new({id="chair-doc",unit="cm",frame={id=frame.id,origin=origin},twoside=false,spreads=P.array(),pages={page}})
local profile=L.profile(definition,{mode="view_only",construction_scale=step})
local recipe=assert(L.recipe(definition,source_spec,doc,page.id,profile,{},{}))
local env=Q.environment({revision="working/chair/"..digest,files={construction=bytes,style={},view={},renderer={}}},
  {lua=_VERSION,host=host},{id=V.VERSION,version="1"})
local result=Q.execute(Q.decode(Q.encode(recipe)),registry,env)
check(result.record.status=="complete",P.serialize(result.record))
check(result.bytes.instance==P.serialize(x.a),"document recipe changed root or leaf set")
local evidence=result.record.extensions.construction
check(evidence.finite and not evidence.globally_queryable and evidence.root_unit_square_count==768,
  "Build record omitted finite coverage")
check(#evidence.checks==6 and result.view.extensions.document.topology_unchanged,"missing finite checks or topology trace")
write("document.recipe",Q.encode(recipe));write("document.scene",result.bytes.scene)
local report={stage="13",source_digest=digest,source=sources,checks=checks,outputs=outputs,shared=shared,query_cuts=cut,
  runtime=_VERSION,host=host,build_record=P.plain(result.record),queries=queries}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("substitutioncheck: "..checks.." checks; "..shared.." shared leaves; source "..digest)
