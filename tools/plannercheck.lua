-- Physical-document and view assertions; independent raster/Fraction checks
-- consume the resulting evidence in planner_oracle.py.
local P,D,L,R,V,H,A=require("pattern"),require("pattern_document"),require("pattern_planner"),require("pattern_registry"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local lfs=require("lfs");local count=0
local function check(ok,message)assert(ok,message);count=count+1 end
local function reject(fn,code)
  local ok,value,diagnostic=pcall(fn)
  check(not ok or value==nil and diagnostic and (not code or diagnostic.code==code),"expected rejected plan "..tostring(code)..": "..tostring(value))
end
local function read(path)local f=assert(io.open(path,"rb"));local s=assert(f:read("*a"));assert(f:close());return s end
local function context()return R.context({seed=7,source={revision="planner-fixture"},limits={objects=10000,operations=100000,bytes=4*1024*1024}})end
local files={};for name in lfs.dir(".")do if name:match('%.lua$')then files[#files+1]=name end end
for _,name in ipairs({"tools/plannercheck.lua","tools/planner_oracle.py","tools/fixtures/planner-grid.lua","docs/validation/fixtures/scene-font.json"})do files[#files+1]=name end
table.sort(files,P.byte_less);local source={};for _,file in ipairs(files)do source[#source+1]={path=file,sha256=H.sha256(read(file):gsub("\r\n","\n"))}end
local digest=H.sha256(P.serialize(source));local root="build/planner/"..digest
for _,path in ipairs({"build","build/planner",root})do if not lfs.mkdir(path)then assert(lfs.dir(path))end end
local function write(name,bytes)return {path=root.."/"..name,sha256=A.write(root.."/"..name,bytes)}end
local registry=R.new();local d,calls=dofile("tools/fixtures/planner-grid.lua").register(registry)
local spec=P.specification({id="grid/spec",definition_ref={id=d.id,version=d.version},parameters={width=14,height=8},inputs={},constraints={},style={},seed=7,document={unit="cm",bounds={0,0,14,8},protected_regions=P.array()}},d)
local generated,problem=registry:generate(d.id,spec,context());assert(generated,problem and P.serialize(problem));local x=generated.instance
local initial=P.serialize(x);local capability=L.profile(d,{mode="fixed_frame",construction_scale=20,maximum_tile_diameter=2})
check(P.serialize(L.import_profile(d,P.plain(capability)))==P.serialize(capability),"planning profile roundtrip")
local function document(id,pages,spreads)
  return D.new({id=id,unit="cm",frame={id="planner/world",origin={0,0}},twoside=true,pages=pages,spreads=spreads or P.array()})
end
local panel=document("panel",{{id="panel",number=1,size={4,3},origin={4.25,2.5},trim={0.25,0.25,3.75,2.75},bleed={0.1,0.1,0.1,0.1},margins={0.4,0.4,0.4,0.4},binding_offset=0.2,offset={0.1,-0.1},
  protected_regions={{id="panel/text",space="page",bounds={1.2,1,2,1.8},role="protected_content"}},anchors={{id="focal",role="focal",space="content",point={0.2,0.3}}}}})
check(P.serialize(D.import(P.plain(panel)))==P.serialize(panel),"document serialized context import")
reject(function()D.page(P.plain(panel),"panel")end)
local corrupt=P.plain(panel);corrupt.pages[1].world_bounds[1]=100;reject(function()D.import(corrupt)end)
reject(function()panel.pages[1].origin[1]=0 end)
local page=D.page(panel,"panel");check(math.abs(page.anchors[1].point[1]-5.4)<1e-12 and math.abs(page.anchors[1].point[2]-3.35)<1e-12,"content anchor includes physical margins/binding/offset once")
local book=document("book",{
  {id="verso",number=2,size={4,3},origin={3,2.5},trim={0.2,0.2,3.8,2.8},bleed={0.1,0.1,0.1,0.1},margins={0.4,0.5,0.6,0.5},binding_offset=0.3,offset={0.1,-0.05},
    protected_regions={{id="callout",space="content",bounds={0.2,0.3,0.9,1.1},role="protected_content"}}},
  {id="recto",number=3,size={4,3},origin={7,2.5},trim={0.2,0.2,3.8,2.8},bleed={0.1,0.1,0.1,0.1},margins={0.6,0.5,0.4,0.5},binding_offset=0.3,offset={-0.1,0.05},
    protected_regions={{id="callout",space="page",bounds={0.4,1.3,1.2,2.1},role="protected_content"}}}},
  {{id="spread/2-3",left="verso",right="recto",gutter=0}})
check(not book.pages[1].recto and book.pages[2].recto and book.pages[1].inner_side=="right" and book.pages[2].inner_side=="left","physical facing-page parity")
check(math.abs(book.pages[1].content[1]-0.7)<1e-12 and math.abs(book.pages[1].content[3]-3)<1e-12 and math.abs(book.pages[2].content[1]-1)<1e-12,"binding/offset content coordinates")
local request,err=L.prepare_specification(d,spec,book,capability,{});assert(request,err and P.serialize(err))
check(request.status=="requires_generator_and_validation" and #request.specification.document.protected_regions==0,"fixed tiling reservations do not enter generation constraints")
check(P.serialize(request.specification.document.bounds)==P.serialize({1,0.5,13,7.5}),"one shared generation halo covers the whole spread")
local bad=P.plain(book);bad.pages[2].origin[1]=0;reject(function()D.import(bad)end)
local overlap=document("overlap",{{id="a",number=2,size={4,2},origin={3,3}},{id="b",number=3,size={4,2},origin={5,3}}})
local output,plans={},{}
local function emit(name,doc,page_id,options)
  local planned,why=L.view(x,d,doc,page_id,capability,options or {require_continuation=true});assert(planned,why and P.serialize(why))
  local lowered,issue=L.lower(registry,d.id,x,d,planned,{},context());assert(lowered,issue and P.serialize(issue))
  local plan=V.plan(lowered.scene,x,lowered.view,d);plans[name]=plan
  local pdf,svg=V.pdf(plan),V.svg(plan)
  output[#output+1]={name=name,pdf=write(name..".pdf",pdf),svg=write(name..".svg",svg),plan=write(name..".plan",P.serialize(plan)),decisions=P.plain(planned.decisions),source_digest=planned.source_digest}
  return planned,lowered
end
local panel_plan=emit("panel",panel,"panel",{region="trim",require_continuation=true})
local full,full_lowered=emit("panel-full",panel,"panel",{region="trim",tile_policy="full_tiles",require_continuation=true})
check(#full.decisions.selection.cell_ids<#panel_plan.decisions.selection.cell_ids,"full-tile and clipped-tile policies differ")
for _,id in ipairs(full.decisions.selection.cell_ids)do check(id=="cell/7/3" or id=="cell/7/4","full tiles are complete and avoid masked cell geometry")end
local left=emit("verso",book,"verso");local right=emit("recto",book,"recto")
local a=emit("overlap-a",overlap,"a");local b=emit("overlap-b",overlap,"b")
local book_pdf=write("book.pdf",V.pdf_document({plans.verso,plans.recto}))
check(#left.decisions.selection.masked_edges>0 and #left.decisions.selection.cut_edges>0,"physical masks and crop cuts retain original edge IDs")
check(left.decisions.selection.continuation_established and right.decisions.selection.continuation_established,"validated patch halo supports both facing pages")
check(calls()==1 and P.serialize(x)==initial,"all document crops reuse one immutable construction without regeneration")
local viewport_generator_calls=calls()
local near=document("near-boundary",{{id="p",number=1,size={2,2},origin={0,0}}})
reject(function()return L.view(x,d,near,"p",capability,{require_continuation=true})end,"insufficient_patch_halo")
reject(function()return L.view(x,d,panel,"panel",capability,{halo=0.1})end)
local exhausted,limit=L.view(x,d,panel,"panel",capability,{},R.context({seed=7,source={revision="planner-budget"},limits={objects=0,operations=100,bytes=100}}))
check(not exhausted and limit.code=="budget_exhausted" and limit.budgets.limits.objects==0,"planning budget failure keeps its receipt")
local cancelled,cancellation=L.view(x,d,panel,"panel",capability,{},R.context({seed=7,source={revision="planner-cancel"},cancelled=function()return true end}))
check(not cancelled and cancellation.status=="cancelled" and cancellation.budgets.cancelled,"planning cancellation is distinct from accepted/rejected geometry")
reject(function()return L.prepare_specification(d,spec,book,capability,{density=0.7})end,"unsupported_intent")
local thin=assert(L.view(x,d,overlap,"a",capability,{minimum_stroke=0.04}))
reject(function()return L.lower(registry,d.id,x,d,thin,{},context())end,"minimum_stroke_unsatisfied")
local good=assert(L.view(x,d,overlap,"a",capability,{minimum_stroke=0.02}))
check(L.lower(registry,d.id,x,d,good,{},context())~=nil,"actual physical stroke constraint passes")
local no_text=assert(L.view(x,d,overlap,"a",capability,{minimum_text_size=0.2}))
reject(function()return L.lower(registry,d.id,x,d,no_text,{},context())end,"text_evidence_missing")
local font=require("pattern_parse").decode(read("docs/validation/fixtures/scene-font.json"))
local td=P.definition({id="fixture/planner-text",version="1",family="positioned-text-fixture",capabilities={"text"},parameters={},units="cm",
  transforms={metric_constrained=false,reflection=true,uniform_scale=true},assumptions={"Positioned real-glyph physical-size fixture; shaping remains stage24"}})
local tx=P.instance({id="text/instance",definition_ref={id=td.id,version=td.version},frame={id="planner/world",dimension=2,unit="cm",handedness="right",origin={0,0}},
  structures={text={runs={{id="text/run",text="Aα",direction="ltr"}},reading_order={"text/run"}}},provenance={generator=td.id,generator_version=td.version,seed=7,construction="actual positioned font fixture"}},td)
local text_registry=R.new();text_registry:register(td,{generate=function()return P.plain(tx)end,validate=function()return {ok=true,checks={"explicit real-font fixture"}}end,
  lower=function(x,v,style)
    for key in pairs(style)do assert(key=="size" or key=="matrix","unsupported text-fixture style")end;local size=style.size or 0.3
    return {id="text/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},reading_order={"text/run"},resources={P.plain(font)},
      operations={{op="text",semantic_ref="text/run",font_ref=font.id,text="Aα",origin={5,3.5},size=size,glyphs={{glyph_ref="glyph/65",offset={0,0}},{glyph_ref="glyph/945",offset={font.glyphs[1].advance/font.units_per_em*size,0}}},
        transform=require("pattern_geometry").compose(v.transform,style.matrix or {1,0,0,0.5,0,1.75}),paint={fill={0.1,0.2,0.4}}}}}
  end})
local text_profile=L.profile(td,{mode="view_only",construction_scale=20})
local text_view=assert(L.view(tx,td,panel,"panel",text_profile,{minimum_text_size=0.2}))
reject(function()return L.lower(text_registry,td.id,tx,td,text_view,{size=0.3},context())end,"minimum_text_size_unsatisfied")
local readable=assert(L.lower(text_registry,td.id,tx,td,text_view,{size=0.6},context()))
check(math.abs(readable.validation.minimum_text_size-0.3)<1e-12,"text constraint measures the actual affine scale")
local affine_cases=P.array()
for _,matrix in ipairs({{0.6,0.8,-0.8,0.6,4.8,-2.6},{1,0.2,0.3,0.9,-1.05,-0.65},{2,0,0,0.5,-5,1.75}})do
  local result,why=L.lower(text_registry,td.id,tx,td,text_view,{size=0.6,matrix=matrix},context());assert(result,why and P.serialize(why))
  affine_cases[#affine_cases+1]={matrix=matrix,size=0.6,measurement=P.plain(result.validation)}
  check(result.validation.minimum_text_size_lower_bound>=0.2,"affine text size established conservatively")
end
local threshold=assert(L.view(tx,td,panel,"panel",text_profile,{minimum_text_size=0.6}))
reject(function()return L.lower(text_registry,td.id,tx,td,threshold,{size=0.6,matrix={0.6,0.8,-0.8,0.6,4.8,-2.6}},context())end,"minimum_text_size_unresolved")
reject(function()return L.lower(text_registry,td.id,tx,td,text_view,{size=0.6,matrix={1,1,1,1+1e-14,0,0}},context())end)
local sd=P.definition({id="fixture/planner-loop",version="1",family="strand-closure-fixture",capabilities={"strands"},parameters={},units="cm",
  transforms={metric_constrained=false,reflection=true,uniform_scale=true},assumptions={"Closed semantic strand; clipping is not a strand edit"}})
local sx=P.instance({id="loop/instance",definition_ref={id=sd.id,version=sd.version},frame={id="planner/world",dimension=2,unit="cm",handedness="right",origin={0,0}},
  structures={strands={components={{id="loop",closed=true,alternating=false,endpoints=P.array(),encounters=P.array()}},crossings=P.array(),ports=P.array()}},provenance={generator=sd.id,generator_version=sd.version,seed=7,construction="closed component fixture"}},sd)
local sv=assert(L.view(sx,sd,panel,"panel",L.profile(sd,{mode="view_only",construction_scale=20}),{}))
check(sv.decisions.strand_topology[1].closed and sv.decisions.strand_topology[1].view_clip_is_not_a_break and #sx.structures.strands.components[1].endpoints==0,"cropping a closed strand does not invent topological endpoints")
local examples,example_definitions=require("pattern_examples").registry();local gd=example_definitions.graph
local gx=assert(examples:generate(gd.id,require("pattern_examples").specification(gd),context())).instance
local graph_document=D.new({id="graph-document",unit="cm",frame={id="example/world",origin={0,0}},twoside=false,pages={{id="graph-page",number=1,size={1,1},origin={0.5,0},
  protected_regions={{id="obstacle",space="page",bounds={0.25,0.625,0.75,0.875},role="protected_content"}}}}})
local gv,graph_error=L.view(gx,gd,graph_document,"graph-page",L.profile(gd,{mode="view_only",construction_scale=8}),{},context());assert(gv,graph_error and P.serialize(graph_error))
check(#gv.decisions.graph_trace.source_endpoints==2 and #gv.decisions.graph_trace.cut_edges==2 and #gv.decisions.graph_trace.masked_edges==2,"graph view cuts/masks retain the two genuine source endpoints")
-- Rational crop classification checks the exact fraction, not rounded1/3.
local exact=require("pattern_exact");local v={exact=exact.point({exact.new(1,3),exact.new(-1,5)})}
check(L.compare_coordinate(v,1,1/3)==1,"exact1/3 exceeds its rounded-down binary64 display")
check(L.compare_coordinate(v,2,-0.2)==1,"exact-1/5 exceeds its rounded-down display")
local numeric_cases=P.array()
for i=-64,64 do for _,den in ipairs({3,5,7,11})do local p={exact=exact.point({exact.new(i,den),exact.new(0)})};local bound=i/den
  numeric_cases[#numeric_cases+1]={numerator=i,denominator=den,bound=bound,comparison=L.compare_coordinate(p,1,bound)}
end end
-- Intent is mapped only to real declared parameters; no ink-percent fiction.
local adaptive=P.definition({id="fixture/adaptive-request",version="1",family="request-contract-fixture",capabilities={"growth"},units="cm",
  parameters={density={type="number",minimum=0.2,maximum=1,required=true},focal={type="integer",minimum=0,maximum=3,required=true}},
  transforms={metric_constrained=false,reflection=true,uniform_scale=true},assumptions={"Request validation fixture; actual floral adaptation uses unchanged legacy implementation"}})
local adaptive_profile=L.profile(adaptive,{mode="adaptive",generation_region="content",construction_scale=20,density_parameter="density",focal_parameter="focal",routing=true})
local adaptive_spec=P.specification({id="adaptive/spec",definition_ref={id=adaptive.id,version=adaptive.version},parameters={density=1,focal=3},inputs={},constraints={},style={},seed=7,document={unit="cm",bounds={0,0,4,3},protected_regions=P.array()}},adaptive)
local adaptive_request=assert(L.prepare_specification(adaptive,adaptive_spec,panel,adaptive_profile,{density=0.3,focal_count=1},"panel"))
check(adaptive_request.specification.parameters.density==0.3 and adaptive_request.specification.parameters.focal==1 and #adaptive_request.specification.document.protected_regions==1,"adaptive request retains declared controls and permitted document context")
check(math.abs(adaptive_request.specification.document.bounds[1]-5.2)<1e-12 and math.abs(adaptive_request.specification.document.bounds[4]-4.75)<1e-12,"adaptive generation uses the family's declared permitted content region")
reject(function()return L.prepare_specification(adaptive,adaptive_spec,panel,adaptive_profile,{density=2},"panel")end)
local path={};for y=1,18,0.25 do path[#path+1]={3,y}end
local route_request={unit="cm",frame="page",points=path,regions={{0,0,6,20}},exclusions={{2,7,4,11}},clearance=0.2}
local before=P.serialize(route_request);local routed,route_error=L.route(adaptive_profile,route_request);assert(routed,route_error and P.serialize(route_error))
check(P.serialize(route_request)==before,"routing owns proposal data")
route_request.exclusions={{-1,7,7,11}};local missing,diagnostic=L.route(adaptive_profile,route_request)
check(not missing and diagnostic.code=="continuous_route_not_found" and P.serialize(diagnostic.details.original_points)==P.serialize(path),"blocked route preserves original samples and useful diagnostic")
reject(function()return L.route(adaptive_profile,{unit="cm",frame="page",points={{1,1},{5,1}},regions={{0,0,2,2},{4,0,6,2}},exclusions=P.array(),clearance=0})end,"route_outside_permitted_region")
-- Saved recipes replay the planner, not a stale list of selected object IDs.
local Q=require("pattern_recipe");local actual_sources={construction={},style={},view={},renderer={}}
for _,file in ipairs(files)do actual_sources.construction[file]=read(file)end
local environment=Q.environment({revision="working/planner/"..digest,files=actual_sources},{lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")},{id="scene-json",version="1"})
local q,recipe_error=L.recipe(d,spec,panel,"panel",capability,{}, {region="trim",tile_policy="full_tiles",require_continuation=true});assert(q,recipe_error and P.serialize(recipe_error))
check(Q.encode(Q.decode(Q.encode(q)))==Q.encode(q),"document recipe saved/loaded with validated physical inputs")
local replay=Q.execute(q,registry,environment)
check(replay.record.status=="complete" and replay.bytes.instance==initial and replay.bytes.scene==P.serialize(full_lowered.scene),"recipe applies actual full-tile selection and exact source scene")
check(replay.record.validation.planning.source_digest==H.sha256(replay.bytes.instance),"BuildRecord binds actual planner validation")
local cropped=assert(L.recipe(d,spec,panel,"panel",capability,{}, {crop={0.5,0.5,3.5,2.5},tile_policy="clipped_tiles",require_continuation=true}))
local keys_a,keys_b=Q.cache_keys(q,environment),Q.cache_keys(cropped,environment)
check(keys_a.structure==keys_b.structure and keys_a.view~=keys_b.view,"fixed-frame crop/policy changes invalidate only view-dependent keys")
local changed=P.plain(panel);changed.pages[1].protected_regions[1].bounds[1]=changed.pages[1].protected_regions[1].bounds[1]+0.1;changed=D.import(changed)
local masked=assert(L.recipe(d,spec,changed,"panel",capability,{}, {region="trim",tile_policy="full_tiles",require_continuation=true}))
local keys_masked=Q.cache_keys(masked,environment)
check(keys_masked.structure==keys_a.structure and keys_masked.view~=keys_a.view,"fixed-frame reservations remain view inputs through cache replay")
local forged=P.plain(q);forged.view.transform[5]=forged.view.transform[5]+1;reject(function()Q.new(forged)end)
reject(function()Q.from_specification(d,spec,full.view,2)end)
local failing=assert(L.recipe(d,spec,panel,"panel",capability,{}, {minimum_stroke=0.04}))
local failed=Q.execute(failing,registry,environment)
check(failed.record.status=="failed" and #failed.record.outputs==0,"unsatisfied planner policy cannot become a complete recipe BuildRecord")
local adaptive_registry=R.new();adaptive_registry:register(adaptive,{
  generate=function(s,c)
    c:consume("objects",1);assert(c.planning and c.planning.page,"prepared adaptive context missing")
    local anchor=c.planning.page.anchors[1].point
    return {id="adaptive/instance",definition_ref={id=adaptive.id,version=adaptive.version},frame=P.plain(c.frame),
      structures={growth={nodes={{id="adaptive/root",point=P.plain(anchor),parameters=P.plain(s.parameters)}},roots={"adaptive/root"}}},
      provenance={generator=adaptive.id,generator_version=adaptive.version,seed=s.seed,construction="explicit anchor/context dataflow fixture"}}
  end,
  validate=function(x)return {ok=#x.structures.growth.nodes==1,checks={"explicit input anchor reaches the semantic growth node"}}end,
  lower=function(x,v,s)
    for key in pairs(s)do error("unsupported adaptive fixture style "..key)end
    local point=require("pattern_geometry").transform(x.structures.growth.nodes[1].point,v.transform)
    return {id="adaptive/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},resources=P.array(),
      operations={{op="path",semantic_ref="adaptive/root",commands={{"M",point[1]-0.1,point[2]-0.1},{"L",point[1]+0.1,point[2]-0.1},{"L",point[1],point[2]+0.1},{"Z"}},paint={fill={0.2,0.5,0.8}}}}}
  end})
local aq=assert(L.recipe(adaptive,adaptive_spec,panel,"panel",adaptive_profile,{density=0.3,focal_count=1},{}))
local ar=Q.execute(aq,adaptive_registry,environment);check(ar.record.status=="complete" and math.abs(ar.instance.structures.growth.nodes[1].point[1]-5.4)<1e-12,"recipe passes actual document anchor/frame to generation")
local moved=P.plain(panel);moved.pages[1].anchors[1].point[1]=moved.pages[1].anchors[1].point[1]+0.2;moved=D.import(moved)
local aq2=assert(L.recipe(adaptive,adaptive_spec,moved,"panel",adaptive_profile,{density=0.3,focal_count=1},{}));local ar2=Q.execute(aq2,adaptive_registry,environment)
check(ar2.record.status=="complete" and Q.cache_keys(aq,environment).structure~=Q.cache_keys(aq2,environment).structure and ar2.bytes.instance~=ar.bytes.instance,"adaptive anchor change invalidates construction and changes actual generated geometry")
local bad_context=P.plain(aq);bad_context.design.extensions.planning_generation.page.anchors[1].point[1]=0;reject(function()Q.new(bad_context)end)
reject(function()adaptive_registry:generate(adaptive.id,adaptive_request.specification,context())end)
-- Actual unchanged floral generation demonstrates adaptation before any clip.
local sp_per_cm=72.27*65536/2.54
local function sp(cm)return math.floor(cm*sp_per_cm+0.5)end
local dimensions={paperwidth=sp(21),paperheight=sp(29.7),oddsidemargin=sp(6.8-2.54),evensidemargin=sp(2.2-2.54),hoffset=sp(0.2),voffset=sp(-0.1),
  textwidth=sp(11.4),textheight=sp(22.4),topmargin=sp(-0.6),headheight=sp(0.4),headsep=sp(0.6),footskip=sp(0.9)}
local F,ink=require("florilegium"),require("ink");local saved={dimen=F.dimen,page=F.page,twoside=F.twoside}
local host_cases=P.array()
for _,number in ipairs({2,3})do for _,side in ipairs({"left","right","outer","inner"})do
  local host_document=D.from_legacy_host({id="host/"..number.."/"..side,frame={id="planner/world",origin={0,0}},twoside=true,pages={{id="page",number=number,origin={0,0},dimensions_sp=dimensions,options={style="quiet",side=side},
    protected_regions={{id="reserved",space="page",bounds={1,8,3,12},role="protected_content"}}}}})
  local case=D.legacy_page(host_document,"page")
  check(case.settings.density==0.3 and case.settings.focal_count==1,"legacy density/focal meaning retained")
  check(F.dimen==saved.dimen and F.page==saved.page and F.twoside==saved.twoside,"legacy temporary host snapshot restored")
  check(host_document.pages[1].binding_offset==0 and host_document.pages[1].offset[1]==0,"already-resolved host offsets/binding are not reapplied")
  host_cases[#host_cases+1]={number=number,side=side,geometry=P.plain(case.geometry),canonical_to_page=P.plain(case.canonical_to_page),document=P.plain(host_document)}
end end
reject(function()D.legacy_geometry(dimensions,3,true,{text_gap=10})end)
check(F.dimen==saved.dimen and F.page==saved.page and F.twoside==saved.twoside,"failed legacy planning restores host state")
local legacy=P.array();local old_backend=ink.backend;local old_transform=ink.get_transform()
-- Explicit fixture inputs: this check must not inherit a prior test's palette
-- or ghost lift when several checkers share a local development runtime.
ink.set_ink(0x24/255,0x56/255,0xC4/255);ink.set_accent(0.71,0.4,0.18);ink.set_lift(0)
for _,blocked in ipairs({false,true})do
  local physical=blocked and {{1,8,5,18}} or P.array()
  local reserved=P.array();for i,b in ipairs(physical)do reserved[#reserved+1]={id="reserve/"..i,space="page",bounds=b,role="protected_content"}end
  local host_document=D.from_legacy_host({id="garden/"..(blocked and "reserved" or "open"),frame={id="planner/world",origin={0,0}},twoside=true,pages={{id="page",number=3,origin={0,0},dimensions_sp=dimensions,options={style="quiet",side="left",header=false},protected_regions=reserved}}})
  local case=D.legacy_page(host_document,"page")
  local g=P.plain(case.geometry);g.seed=7;g.spill=0;g.spilly=19;g.visitors=false;g.marks=P.array()
  local writer=require("pdfwriter").new();ink.set_backend(writer.backend);writer:begin()
  ink.set_page_transform(g.mirror and {-1,0,0,1,g.pw*ink.CM,0} or nil);ink.set_page_clip(g.pw,g.ph,g.reserves)
  local stats=require("grow").page(g);ink.set_page_transform(nil);ink.set_page_clip(nil,nil,nil)
  writer:finish(g.pw*ink.CM,g.ph*ink.CM)
  local name="legacy-"..(blocked and "reserved-" or "open-").._VERSION:gsub(' ','-')..".pdf"
  local temp=root.."/host-output-".._VERSION:gsub(' ','-')..".pdf"
  for _,name in ipairs({temp,temp..".tmp"})do local existing=io.open(name,"rb");if existing then existing:close();error("unfinished legacy host PDF must be investigated")end end
  writer:write(temp);local bytes=read(temp);assert(os.remove(temp));local artifact=write(name,bytes)
  legacy[#legacy+1]={kind=blocked and "reserved" or "open",pdf=artifact,physical_reservations=P.plain(physical),stats=stats,geometry=P.plain(g),document=P.plain(host_document)}
end
ink.set_backend(old_backend);ink.set_transform(old_transform)
check(legacy[2].stats.cells<legacy[1].stats.cells,"actual garden occupancy adapts to permitted space before clipping")
check(legacy[2].stats.skipped>0,"actual motif transactions reject reserved-region geometry")
local report={stage="07",status="local_planning_checks_passed",source_digest=digest,source=source,host=PATTERN_TEST_HOST or _VERSION,checks=count,
  instance_sha256=H.sha256(initial),generator_calls=viewport_generator_calls,recipe_generator_calls=calls()-viewport_generator_calls,documents={panel=P.plain(panel),book=P.plain(book),overlap=P.plain(overlap)},generation_request=P.plain(request),adaptive_request=P.plain(adaptive_request),outputs=output,book_pdf=book_pdf,
  overlap_world_bounds={5,3,7,5},numeric_comparisons=numeric_cases,route=P.plain(routed),blocked_route=P.plain(diagnostic),legacy=legacy,legacy_host={dimensions_sp=dimensions,cases=host_cases},
  recipe_replay={fixed_build=P.plain(replay.record),rejected_build=P.plain(failed.record),fixed_keys=P.plain(keys_a),cropped_keys=P.plain(keys_b),masked_keys=P.plain(keys_masked),adaptive_builds={P.plain(ar.record),P.plain(ar2.record)},adaptive_keys={P.plain(Q.cache_keys(aq,environment)),P.plain(Q.cache_keys(aq2,environment))},adaptive_points={P.plain(ar.instance.structures.growth.nodes[1].point),P.plain(ar2.instance.structures.growth.nodes[1].point)},
    files={recipe=write("recipe-fixed.json",Q.encode(q)),instance=write("recipe-full.instance",replay.bytes.instance),scene=write("recipe-full.scene",replay.bytes.scene),adaptive_a=write("recipe-adaptive-a.instance",ar.bytes.instance),adaptive_b=write("recipe-adaptive-b.instance",ar2.bytes.instance)}},
  legacy_style={ink={0x24/255,0x56/255,0xC4/255},accent={0.71,0.4,0.18},lift=0},positioned_text_measurement=P.plain(readable.validation),affine_measurements=affine_cases,closed_strand_view=P.plain(sv.decisions.strand_topology)}
write("receipt-".._VERSION:gsub(' ','-')..".json",P.serialize(report))
print("plannercheck: "..count.." checks passed; one immutable grid, standalone/facing/overlap PDF/SVG views; evidence "..root)
return report
