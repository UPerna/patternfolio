local P,R,E,D,L,Q=require("pattern"),require("pattern_registry"),require("pattern_examples"),require("pattern_document"),require("pattern_planner"),require("pattern_recipe")
local F=require("pattern_spectre")
local A,H,V=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs")
local reference="docs/validation/fixtures/spectre-reference-hashes.json"
local names={"tools/spectrecheck.lua","tools/spectre_oracle.py",reference}
for n in fs.dir(".") do if n:match("%.lua$") then names[#names+1]=n end end
table.sort(names,P.byte_less)
local source,bytes={},{}
for _,n in ipairs(names) do
  local f=assert(io.open(n,"rb"));bytes[n]=f:read("*a"):gsub("\r\n","\n");f:close()
  source[#source+1]={path=n,sha256=H.sha256(bytes[n])}
end
local digest=H.sha256(P.serialize(source))
local root="build/spectre/"..digest
for _,d in ipairs{"build","build/spectre",root} do fs.mkdir(d) end
local outputs={}
local function write(n,data) outputs[n]=A.write(root.."/"..n,data) end
local registry=R.new();local definition=F.register(registry)
local frame={id="spectre/world",dimension=2,unit="cm",handedness="right",origin={.25,.125}}
local limits={objects=30000,operations=400000,bytes=32*1024*1024}
local host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")
local function ctx()
  return R.context({seed=15,frame=frame,limits=limits,source={revision="working/spectre/"..digest}})
end
local function spec(n,box,params)
  params.edge_length=.25
  return P.specification({id="fixture/"..n,definition_ref={id=definition.id,version=definition.version},seed=15,
    parameters=params,inputs={},constraints={},style={},budget=limits,document={unit="cm",bounds=box,protected_regions=P.array()}},definition)
end
local function generate(s)
  local r,e=registry:generate(definition.id,s,ctx());assert(r,e and P.serialize(e))
  return r.instance
end
local function render(n,x,box)
  local v=E.view(x,definition,box)
  local scene=registry:lower(definition.id,x,v,{},ctx())
  local plan=V.plan(scene,x,v,definition)
  write(n..".pdf",V.pdf(plan));write(n..".svg",V.svg(plan))
  return scene
end
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function reject(f,needle)
  local ok,e=pcall(f)
  check(not ok and tostring(e):find(needle,1,true),tostring(e))
end
local function eq(a,b) return P.serialize(a)==P.serialize(b) end
local function index(a)
  local m={};for _,v in ipairs(a) do m[v.id]=v end;return m
end
local expected=require("pattern_parse").decode(bytes[reference])
local references={}
for _,g in ipairs(expected) do
  local actual=F.check_root(g.depth,g.name)
  check(actual.leaves==g.count and actual.digest==g.digest,"authors' coordinate fixture mismatch")
  references[#references+1]={root=g.name,depth=g.depth,count=actual.leaves,digest=actual.digest,proof=actual.proof}
end
local boxes={whole={-1.5,-6,6.2,1.55},a={-1.1,-3.9,2.05,.3},b={0,-2.4,3.95,.7},
  common={.35,-2.15,1.9,.15},detail={.35,-1.9,1.85,-.6},deep={-.7,-4,3,-1.5}}
local specs={
  curved=spec("curved",boxes.whole,{depth=2,whole_root=true}),
  straight=spec("straight",boxes.whole,{depth=2,whole_root=true,boundary="tile-1-1"}),
  a=spec("a",boxes.a,{depth=2}),b=spec("b",boxes.b,{depth=2}),
  deep=spec("deep",boxes.deep,{depth=3}),
}
local x={}
for _,n in ipairs{"curved","straight","a","b","deep"} do
  x[n]=generate(specs[n])
  write(n..".instance",P.serialize(x[n]))
end
check(x.curved.extensions.spectre.certificate.strictly_chiral
  and not x.straight.extensions.spectre.certificate.strictly_chiral,"straight diagnostic mislabeled")
check(eq(x.curved.structures.tiling.cells,x.straight.structures.tiling.cells),"boundary choice changed lineage")
check(x.deep.extensions.spectre.certificate.root_leaf_count==488,"depth 3 root count")
local global=index(x.curved.structures.tiling.cells)
local a,b=index(x.a.structures.tiling.cells),index(x.b.structures.tiling.cells)
local shared=0
for id,c in pairs(a) do
  assert(eq(c,global[id]),"query changed source transform")
  if b[id] then assert(eq(c,b[id]),"overlap changed source lineage");shared=shared+1 end
end
check(shared>0 and #x.a.structures.tiling.cells<#x.curved.structures.tiling.cells,"no selective crop witness")
local g=index(x.curved.structures.tiling.edges)
for _,e in ipairs(x.a.structures.tiling.edges) do
  assert(eq(e.global_cells,g[e.id].global_cells) and eq(e.curve,g[e.id].curve),"crop changed shared curved edge")
end
check(x.a.extensions.spectre.certificate.query_cuts>0,"no classified cut edge")
local cs=render("curved",x.curved,boxes.whole)
local ss=render("straight",x.straight,boxes.whole)
local cubic,lines=0,0
for _,op in ipairs(cs.operations) do for _,q in ipairs(op.commands) do if q[1]=="C" then cubic=cubic+1 end end end
for _,op in ipairs(ss.operations) do for _,q in ipairs(op.commands) do if q[1]=="L" then lines=lines+1 end;assert(q[1]~="C") end end
check(cubic>0 and lines==cubic,"genuine curved path absent or diagnostic changed the edge count")
render("crop-a",x.a,boxes.a);render("crop-b",x.b,boxes.b)
render("common-a",x.a,boxes.common);render("common-b",x.b,boxes.common)
render("detail-curved",x.curved,boxes.detail);render("detail-straight",x.straight,boxes.detail)
render("deep",x.deep,boxes.deep)
check(outputs["common-a.pdf"]==outputs["common-b.pdf"] and outputs["common-a.svg"]==outputs["common-b.svg"],
  "same physical view altered curved vectors")
local raw=P.plain(x.a);raw.structures.tiling.cells[1].exact_transform.reflected=true
reject(function()F.validate(raw)end,"spectre-illicit-reflected-leaf")
raw=P.plain(x.a)
for _,e in ipairs(raw.structures.tiling.edges) do
  if e.role=="interior" then e.curve.control1,e.curve.control2=e.curve.control2,e.curve.control1;break end
end
reject(function()F.validate(raw)end,"spectre-incorrectly-paired-curve")
raw=P.plain(x.a);raw.structures.tiling.hierarchy[1].type="Invented"
reject(function()F.validate(raw)end,"spectre-source-hierarchy-reconstruction")
reject(function()render("outside",x.a,boxes.whole)end,"spectre-view-outside-query")
local v=boxes.common;local w,h=v[3]-v[1],v[4]-v[2]
local page={id="panel",number=1,size={w,h},origin={v[1],v[2]},trim={0,0,w,h},bleed={0,0,0,0},
  margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions=P.array()}
local document=D.new({id="spectre-doc",unit="cm",frame={id=frame.id,origin=frame.origin},twoside=false,spreads=P.array(),pages={page}})
local profile=L.profile(definition,{mode="view_only",construction_scale=.25})
local recipe=assert(L.recipe(definition,specs.a,document,page.id,profile,{},{}))
local env=Q.environment({revision="working/spectre/"..digest,files={construction=bytes,style={},view={},renderer={}}},
  {lua=_VERSION,host=host},{id=V.VERSION,version="1"})
local build=Q.execute(Q.decode(Q.encode(recipe)),registry,env)
check(build.record.status=="complete",P.serialize(build.record))
check(build.bytes.instance==P.serialize(x.a) and build.record.extensions.construction.strictly_chiral,
  "document recipe changed construction or geometry case")
write("document.recipe",Q.encode(recipe));write("document.scene",build.bytes.scene)
local report={stage="15",source_digest=digest,source=source,checks=checks,outputs=outputs,references=references,
  shared=shared,boxes=boxes,runtime=_VERSION,host=host,build_record=P.plain(build.record)}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("spectrecheck: "..checks.." checks; "..shared.." shared Spectre leaves; source "..digest)
