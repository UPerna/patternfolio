-- Analytical/adversarial checks plus immutable reports for the independent oracle.
local P,G,C,B,S,T,E,N,H,D=require("pattern"),require("pattern_geometry"),require("pattern_curves"),require("pattern_bounds"),require("pattern_spatial"),require("pattern_topology"),require("pattern_exact"),require("pattern_predicates"),require("pattern_hash"),require("pattern_random")
local lfs=require("lfs");local count=0
local function check(ok,why) assert(ok,why);count=count+1 end
local function reject(fn)check(not pcall(fn),"expected geometry rejection")end
local function read(p)local f=assert(io.open(p,"rb"));local v=f:read("*a");f:close();return v end
local fixture=require("pattern_parse").decode(read("docs/validation/fixtures/geometry-v1.json"))
local policy=G.policy("cm",8);local tol=G.tolerance(policy)
for _,v in ipairs(fixture.orientation)do check(N.orient2d(v.points[1],v.points[2],v.points[3])==v.sign,"preserved exact orientation counterexample")end
reject(function()N.orient2d({1e100,0},{0,0},{1,1})end)
local m={-2,0,0.3,1,5,-2};local inv=G.inverse(m,policy);local q=G.transform(G.transform({1,2},m),inv)
check(math.abs(q[1]-1)<tol and math.abs(q[2]-2)<tol,"reflected affine roundtrip")
local composed=G.compose(inv,m);q=G.transform({2,3},composed);check(math.abs(q[1]-2)<tol and math.abs(q[2]-3)<tol,"affine composition order")
reject(function()G.inverse({1,1,1,1+2^-52,0,0},policy)end)
reject(function()G.compose({1e200,0,0,1e200,0,0},{1e200,0,0,1e200,0,0})end)
for _,scale in ipairs({1e-9,1,1e9})do
  local p=G.policy("cm",4*scale)
  local hit=G.segment_intersection({0,0},{2*scale,2*scale},{0,2*scale},{2*scale,0},p)
  check(hit.kind=="point" and math.abs(hit.point[1]-scale)<=G.tolerance(p),"scale-aware crossing")
end
check(G.segment_intersection({0,0},{2,0},{1,0},{3,0},policy).kind=="overlap","coincident segment interval")
check(G.segment_intersection({0,0},{1,0},{1,0},{1,1},policy).classification=="endpoint","shared endpoint")
check(G.segment_intersection({0,0},{0,0},{0,1},{1,1},policy).kind=="degenerate","zero-length is not empty")
local outer={{0,0},{4,0},{4,4},{0,4}};local hole={{1,1},{1,3},{3,3},{3,1}}
local region=G.region(outer,{hole},policy)
local recovered=G.import_region(require("pattern_parse").decode(P.serialize(region)),policy)
check(G.contains(recovered,{2,2})=="outside","region serialization revalidates holes")
reject(function()G.contains(P.plain(region),{2,2})end)
reject(function()G.region(outer,{[1]=hole,[3]=hole},policy)end)
reject(function()G.region(outer,{ignored_hole=hole},policy)end)
reject(function()G.region(outer,{},policy,{max_pair_checks=0})end)
reject(function()P.snapshot({[1]=1,[3]=3})end)
reject(function()P.snapshot(setmetatable({},{__jsontype="object",__index=function()return 1 end}))end)
check(G.contains(region,{0.5,2})=="inside" and G.contains(region,{2,2})=="outside" and G.contains(region,{1,2})=="boundary","region and hole membership")
local clip=G.clip_segment(region,{-1,2},{5,2},policy)
check(clip.status=="complete" and #clip.segments==2 and clip.segments[1].from[1]==0 and clip.segments[1].to[1]==1 and clip.segments[2].from[1]==3 and clip.segments[2].to[1]==4,"analytic hole clipping, distance return regression")
local square=G.region(outer,{},policy);local touch=G.clip_segment(square,{-1,1},{1,-1},policy)
check(touch.status=="complete" and not touch.empty and #touch.segments==0 and #touch.contacts==1,"zero-dimensional corner contact")
check(G.clip_segment(square,{-1,5},{5,5},policy).empty,"verified empty clip")
check(G.clip_segment(square,{1,1},{1,1},policy).status=="degenerate","degenerate clip")
check(G.clip_segment(square,{4+1e-12,0},{4+1e-12,4},policy).status=="unresolved","near-boundary ambiguity is explicit")
local precise=G.policy("cm",8,0)
check(G.clip_segment(square,{4+1e-12,0},{4+1e-12,4},precise).empty,"same near miss resolved under tighter valid policy")
local narrow=G.region({{0,0},{1,0},{1,1e-7},{0,1e-7}},{},G.policy("cm",1))
check(#G.clip_segment(narrow,{-1,5e-8},{2,5e-8},G.policy("cm",1)).segments==1,"narrow corridor retained")
reject(function()G.region({{0,0},{4,4},{0,4},{4,0}},{},policy)end)
reject(function()G.region({{0,0},{0,4},{4,4},{4,0}},{},policy)end)
reject(function()G.region(outer,{{{5,1},{5,2},{6,2},{6,1}}},policy)end)
reject(function()G.region(outer,{hole,{{1.5,1.5},{1.5,2.5},{2.5,2.5},{2.5,1.5}}},policy)end)
local crossing={{-3,-3},{-1,-1},{1,1},{3,3}};local tangent={{-3,3},{-1,-1},{1,-1},{3,3}}
local hit=C.intersect_segment(crossing,{-4,0},{4,0},policy)
check(hit.status=="complete" and #hit.events==1 and hit.events[1].curve_parameter==0.5 and hit.events[1].classification=="crossing","certified cubic-line crossing")
local fractional=C.intersect_segment({{0,-1},{0.25,0},{0.75,1},{1,2}},{-1,0},{2,0},policy)
check(fractional.status=="complete" and #fractional.events==1 and fractional.events[1].curve_interval[1]<fractional.events[1].curve_interval[2],"non-dyadic simple root uses interval refinement")
hit=C.intersect_segment(tangent,{-4,0},{4,0},policy)
check(hit.status=="complete" and #hit.events==1 and hit.events[1].classification=="tangent" and hit.events[1].multiplicity==2,"exact dyadic tangency")
check(C.intersect_segment({{-3,3},{-1,-3},{1,0},{3,12}},{-4,0},{4,0},policy).status=="unresolved","non-dyadic repeated root stays explicit")
check(C.intersect_segment({{0,0},{1,0},{2,0},{3,0}},{-1,0},{4,0},policy).status=="unresolved","coincident curve is not empty")
check(C.intersect_segment(crossing,{-4,0},{4,0},policy,{max_nodes=1}).status=="unresolved","curve budget cannot accept partial roots")
check(C.intersect_segment({{1,1},{1,1},{1,1},{1,1}},{0,0},{2,0},policy).status=="degenerate","constant curve classified")
reject(function()C.intersect_cubics(crossing,tangent,policy)end)
reject(function()C.intersect_segment(crossing,{-4,0},{4,0},policy,{precision=1e-30})end)
local arch={{0,0},{0,1},{1,1},{1,0}};local box=C.tight_bounds(arch,policy)
check(math.abs(box[4]-0.75)<2*tol,"analytic cubic ymax")
local left,right=C.split(arch,0.5);local midpoint=C.evaluate(arch,0.5)
check(left[4][1]==midpoint[1] and right[1][2]==midpoint[2],"de Casteljau split preserves midpoint")
local path={{"M",0,0},{"L",1,0}}
local bounds=B.path(path,{stroke={0,0,0},stroke_width=0.2,cap="round",join="round"},nil,policy)
check(bounds.bounds[1]<=-0.1 and bounds.bounds[3]>=1.1 and bounds.bounds[2]<=-0.1 and bounds.bounds[4]>=0.1,"round-cap stroke bounds")
local reflected=B.path(path,{stroke={0,0,0},stroke_width=0.2,cap="square",join="miter",miter_limit=4},m,policy)
check(reflected.bounds[1]<3 and reflected.bounds[3]>5 and reflected.bounds[2]<-2 and reflected.bounds[4]>-2,"affine square-cap/miter envelope")
check(B.path({{"M",0,0}},{fill={1,0,0}},nil,policy).empty and B.union({},"cm").empty,"legitimate empty paths/unions")
reject(function()B.box({1,0,0,1})end)
local index=S.new(3);local original={0,0,1,1};index:insert("b",original);original[3]=100;index:insert("a",{0,0,0.5,0.5});index:insert("c",{2,2,3,3})
local matches=index:query({0,0,0.25,0.25});check(#matches==2 and matches[1]=="a" and matches[2]=="b","spatial tie ordering")
check(#index:query({50,0,51,1})==0,"spatial bounds are owned copies")
reject(function()index:insert("d",{0,0,1,1})end)
local Examples,R=require("pattern_examples"),require("pattern_registry");local registry,defs=Examples.registry();local instances={}
for _,name in ipairs({"graph","tiling"})do
  local built=assert(registry:generate(defs[name].id,Examples.specification(defs[name]),R.context({seed=7,source={revision="geometry-fixture"}})));instances[name]=built.instance
  local report=T.inspect(built.instance,defs[name],policy);check(report.ok,P.serialize(report.errors))
  check(#report.checks>0 and #report.components[name]==1,"inspectable connectivity")
end
local tile=instances.tiling;local inspect=T.inspect(tile,defs.tiling,policy)
check(inspect.cell_adjacency["tile/A"][1]=="tile/B" and #inspect.owners==7,"shared edge ownership and adjacency")
local exact=P.plain(tile)
for _,v in ipairs(exact.structures.tiling.vertices)do v.exact=E.point({E.new(v.point[1]),E.new(v.point[2])});v.point=nil end
exact=P.instance(exact,defs.tiling);check(T.inspect(exact,defs.tiling,policy).ok,"exact rational tile geometry")
check(P.serialize(P.deserialize(P.serialize(exact),"instance",defs.tiling))==P.serialize(exact),"topology-preserving exact serialization")
check(#T.ancestors(exact,"tile/A")==1,"construction ancestry")
local function ep(x,y)return E.point({E.new(x),E.new(y)})end
local ex=G.intersect_exact_segments(ep(0,0),ep(1,1),ep(0,1),ep(1,0))
check(ex.exact.components[1][1]==1 and ex.exact.components[1][2]==2,"exact rational intersection without float construction")
local projected,receipt=G.render_vertex({exact=E.point({E.new(1,3),E.new(1,6)})})
check(projected[1]==1/3 and receipt.operation=="rational-to-binary64-v1" and receipt.absolute_error_bounds[1]>0,"explicit rendering conversion")
reject(function()E.new(1,0)end);reject(function()E.mul(E.new(E.MAX_COMPONENT),E.new(E.MAX_COMPONENT))end)
local invalid=P.plain(exact);invalid.structures.tiling.vertices[1].point={0,0};reject(function()P.instance(invalid,defs.tiling)end)
invalid=P.plain(tile);invalid.structures.tiling.edges[1].owner="missing";check(not T.inspect(invalid,defs.tiling,policy).ok,"corrupted incidence")
invalid=P.plain(tile);local boundary=invalid.structures.tiling.cells[1].boundary;boundary[1],boundary[2]=boundary[2],boundary[1]
check(not T.inspect(invalid,defs.tiling,policy).ok,"broken boundary walk")
local graph=P.plain(instances.graph);graph.structures.graph.vertices[4]={id="graph/d",point={1,-1}};graph.structures.graph.edges[1].to="graph/c";graph.structures.graph.edges[2].from="graph/b";graph.structures.graph.edges[2].to="graph/d"
check(not T.inspect(graph,defs.graph,policy).ok,"crossing planar graph detected")
check(T.inspect(graph,defs.graph,policy,{allow_crossings=true}).ok,"explicit nonplanar graph observation policy")
check(not T.inspect(graph,defs.graph,policy,{allow_crossings="yes"}).ok,"crossing policy must be explicit boolean")
graph=P.plain(instances.graph);graph.structures.graph.edges[3]={id="duplicate",from="graph/a",to="graph/b"}
check(not T.inspect(graph,defs.graph,policy).ok,"duplicate endpoint pair")
graph=P.plain(instances.graph);graph.structures.graph.vertices[4]={id="coincident",point={0,0}}
check(not T.inspect(graph,defs.graph,policy).ok,"coincident identities are not silently snapped")
check(not T.inspect(tile,defs.tiling,policy,{max_pair_checks=0}).ok,"topology budget fails explicitly")
local strand_def=P.plain(defs.graph);strand_def.id="fixture/strand";strand_def.capabilities={"strands"};strand_def=P.definition(strand_def)
local strand=P.plain(instances.graph);strand.definition_ref={id=strand_def.id,version=strand_def.version};strand.provenance.generator=strand_def.id
strand.structures={strands={ports=P.array(),crossings={{id="self",over="loop",under="loop",self_crossing=true,point={0,0}}},components={{id="loop",closed=true,alternating=true,endpoints=P.array(),encounters={{crossing="self",role="over"},{crossing="self",role="under"}}}}}}
strand=P.instance(strand,strand_def);local walk=T.strand(strand,"loop")
check(walk.closed and walk.alternating and walk.encounters[1].role=="over" and walk.encounters[2].role=="under","ordered closed strand traversal")
local floral=assert(registry:generate(defs.floral.id,Examples.specification(defs.floral),R.context({seed=7,source={revision="geometry-fixture"}}))).instance
local tree=P.plain(floral);tree.structures.growth.nodes[2]={id="branch",parent="floral/root",point={3,4}};tree.structures.growth.nodes[3]={id="leaf",parent="branch",point={3,5}}
tree=P.instance(tree,defs.floral);local lineage=T.ancestors(tree,"leaf")
check(#lineage==2 and lineage[1]=="branch" and lineage[2]=="floral/root","multi-level growth ancestry")
-- Deterministic fresh corpus; Python checks exact Fractions of the emitted binary64 inputs.
local report={schema_version=1,seed=505031,runtime=_VERSION,orientations=P.array(),segments=P.array(),curves=P.array(),general_curves=P.array(),bounds=P.array()};local rng=D.new(505031)
for i=1,2000 do
  local scale=10.0^rng.int(-30,30);local a={rng.range(-3,3)*scale,rng.range(-3,3)*scale};local b={rng.range(-3,3)*scale,rng.range(-3,3)*scale};local c
  if i%2==0 then local t=rng.u();c={a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2])}else c={rng.range(-3,3)*scale,rng.range(-3,3)*scale}end
  local sign=N.orient2d(a,b,c);report.orientations[#report.orientations+1]={points={a,b,c},sign=sign}
end
for _,case in ipairs({
  {controls={{0,-1},{0.25,0},{0.75,1},{1,2}},roots={{1,3}}},
  {controls={{0,-18},{0.25,37},{0.75,-58},{1,72}},roots={{1,5},{2,5},{3,5}}},
})do report.general_curves[#report.general_curves+1]={controls=case.controls,rational_roots=case.roots,result=C.intersect_segment(case.controls,{-1,0},{2,0},policy)}end
for i=1,500 do
  local a,b,c,d={rng.int(-1000,1000),rng.int(-1000,1000)},{rng.int(-1000,1000),rng.int(-1000,1000)},{rng.int(-1000,1000),rng.int(-1000,1000)},{rng.int(-1000,1000),rng.int(-1000,1000)}
  if i%5==0 then a[2]=0;b[2]=0;c[2]=0;d[2]=0 elseif i%7==0 then c={b[1],b[2]}elseif i%17==0 then b={a[1],a[2]}end
  report.segments[#report.segments+1]={points={a,b,c,d},result=G.segment_intersection(a,b,c,d,G.policy("cm",4000))}
end
for i=1,64 do
  local r,s,t=rng.int(1,7)/8,rng.int(1,7)/8,rng.int(1,7)/8
  local a0,a1,a2=-3*r*s*t,3*(r*s+r*t+s*t),-3*(r+s+t)
  local c={{0,a0},{0.25,a0+a1/3},{0.75,a0+2*a1/3+a2/3},{1,a0+a1+a2+3}}
  report.curves[#report.curves+1]={controls=c,factored_roots={r,s,t},result=C.intersect_segment(c,{-1,0},{2,0},policy)}
end
for i=1,128 do
  local controls={};for j=1,4 do controls[j]={rng.int(-10,10),rng.int(-10,10)}end
  local matrix={-2,0.3,0.4,1.5,5,-2}
  local path={{"M",controls[1][1],controls[1][2]},{"C",controls[2][1],controls[2][2],controls[3][1],controls[3][2],controls[4][1],controls[4][2]}}
  report.bounds[#report.bounds+1]={controls=controls,matrix=matrix,stroke_width=0.2,result=B.path(path,{stroke={0,0,0},stroke_width=0.2,cap="round",join="round"},matrix,policy)}
end
local source={};for name in lfs.dir(".")do if name:match('%.lua$')then source[name]=H.sha256(read(name))end end
for _,name in ipairs({"tools/geometrycheck.lua","tools/geometry_oracle.py","docs/validation/fixtures/geometry-v1.json"})do source[name]=H.sha256(read(name))end
report.source_digest=H.sha256(P.serialize(source));report.analytical_checks=count
local bytes=P.serialize(report);lfs.mkdir("build");lfs.mkdir("build/geometry-oracle")
local key=H.sha256(bytes);assert(require("pattern_store").new("build/geometry-oracle"):put(key,bytes))
print("geometrycheck: "..count.." analytical/adversarial checks passed; oracle corpus2000 orientations/500 segments/66 cubics/128 bounds, source "..report.source_digest..", cache "..key)
