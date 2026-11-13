-- Source-bound acceptance fixtures for periodic geometry and real document views.
package.path="./?.lua;"..package.path
local P,R,D,L,Q=require("pattern"),require("pattern_registry"),require("pattern_document"),require("pattern_planner"),require("pattern_recipe")
local F,T,W,G=require("pattern_periodic"),require("pattern_periodic_templates"),require("pattern_wallpaper"),require("pattern_geometry")
local A,H,Render=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs");local files={"tools/periodiccheck.lua","tools/periodic_oracle.py"}
for name in fs.dir(".")do if name:match("%.lua$")then files[#files+1]=name end end
table.sort(files,P.byte_less)
local sources,bytes={},{}
for _,name in ipairs(files)do local f=assert(io.open(name,"rb"));bytes[name]=f:read("*a");f:close();sources[#sources+1]={path=name,sha256=H.sha256(bytes[name]:gsub("\r\n","\n"))}end
local digest=H.sha256(P.serialize(sources));local root="build/periodic/"..digest
for _,p in ipairs({"build","build/periodic",root})do fs.mkdir(p)end
local outputs={}
local function write(name,data)outputs[name]=A.write(root.."/"..name,data)end
local checks=0;local function check(ok,msg)assert(ok,msg);checks=checks+1 end
local registry=R.new();local definition=F.register(registry)
local origin={-0.4,0.7};local frame={id="periodic/world",unit="cm",dimension=2,handedness="right",origin=origin}
local limits={objects=20000,operations=400000,bytes=32*1024*1024}
local function ctx(planning,limit,cancelled)
 return R.context({seed=7,source={revision="working/periodic/"..digest},frame=frame,planning=planning,limits=limit or limits,cancelled=cancelled})
end
local function doc(id,at,mask)
 return D.new({id=id,unit="cm",frame={id=frame.id,origin=origin},twoside=false,spreads=P.array(),
  pages={{id="panel",number=1,size={3.2,2.8},origin=at,trim={0,0,3.2,2.8},bleed={0,0,0,0},margins={0,0,0,0},binding_offset=0,offset={0,0},
    protected_regions=mask and {{id="callout",role="protected_content",space="page",bounds={1.25,0.9,1.85,1.55}}}or P.array()}}})
end
local function spec(family,step,angle,group)
 return P.specification({id="periodic/"..family,definition_ref={id=definition.id,version=definition.version},seed=7,
   parameters={family=family,lattice_step=step,rotation_degrees=angle,wallpaper=group},inputs={},constraints={},style={marker=true},budget=limits,
   document={unit="cm",bounds={-2,-1,2,2},protected_regions=P.array()}},definition)
end
local function generate(s,document,profile)
 local request=assert(L.prepare_specification(definition,s,document,profile,{}))
 local c=ctx(request.specification.extensions.planning_generation)
 local out,problem=registry:generate(definition.id,request.specification,c);assert(out,problem and P.serialize(problem));return out.instance,c,request
end
local function render(name,x,c,document,profile,opts,record_instance)
 local plan,error_=L.view(x,definition,document,"panel",profile,opts,c);assert(plan,error_ and P.serialize(error_))
 local drawn,problem=L.lower(registry,definition.id,x,definition,plan,{marker=true},c);assert(drawn,problem and P.serialize(problem))
 local drawing=Render.plan(drawn.scene,x,drawn.view,definition)
 write(name..".pdf",Render.pdf(drawing));write(name..".svg",Render.svg(drawing));write(name..".plan",P.serialize(drawing))
 if record_instance then write(name..".instance",P.serialize(x))end
 return plan,drawn
end
local function index(t)local out={};for _,v in ipairs(t)do out[v.id]=v end;return out end
local function equal(a,b)return P.serialize(a)==P.serialize(b)end
local names,templates,groups,fixtures=T.names(),{}, {}, {}
for _,name in ipairs(W.names())do
 local g=W.group(name,(name=="p3"or name=="p6"or name=="p6m")and"hexagonal"or"square");groups[#groups+1]=P.plain(g)
 for _,a in ipairs(g.operations)do
   local left=W.element(g,a.id,{-3,5});local inv=W.compose(g,left,W.inverse(g,left))
   assert(inv.operation=="r0"and inv.translation[1]==0 and inv.translation[2]==0)
   for _,b in ipairs(g.operations)do
    local right=W.element(g,b.id,{2,-1});local p={0.125,0.375}
    local single,chirality=W.apply(g,W.compose(g,left,right),p);local twice=W.apply(g,left,W.apply(g,right,p))
    assert(equal(single,twice)and chirality==a.orientation*b.orientation,"affine group composition failed")
   end
   local p=W.apply(g,left,{0,0});local q=W.apply(g,left,{0.3,0.1});local r=W.apply(g,left,{0.02,0.27})
   assert(require("pattern_predicates").orient2d(p,q,r)==a.orientation,"asymmetric group motif has unexpected reflection")
 end
 check(true,name.." affine action")
end
check(not pcall(W.group,"p4g","square")and not pcall(W.group,"p6m","square"),"unsupported or nonmetric group accepted")
write("groups.json",P.serialize(groups))
local primary_doc=doc("panel-a",{-2.2,-1.4});local first,first_plan
local step=2.2;local profile=F.profile(definition,step)
for _,name in ipairs(names)do
 local s=spec(name,step,23);local x,c=generate(s,primary_doc,profile)
 local plan=render(name,x,c,primary_doc,profile,{tile_policy="clipped_tiles",require_continuation=true},true)
 local pp=x.extensions.periodic;local a=x.structures.tiling
 check(pp.integer_query[1]<0 and pp.integer_query[3]>0 and plan.decisions.selection.continuation_established,"missing world halo or signed addresses")
 check(#plan.decisions.selection.cut_edges>0 and #a.cells>#plan.decisions.selection.cell_ids,"crop did not preserve distinct source topology")
 fixtures[#fixtures+1]={name=name,origin={-2.2,-1.4},size={3.2,2.8},cells=#a.cells,edges=#a.edges,vertices=#a.vertices,selected=#plan.decisions.selection.cell_ids}
 templates[#templates+1]=P.plain(T.get(name))
 if name=="4.6.12"then first,first_plan=x,plan end
end
write("templates.json",P.serialize(templates))
local s=spec("4.6.12",step,23);local secondary_doc=doc("panel-b",{-0.8,-1.4})
local second,c2=generate(s,secondary_doc,profile)
local second_plan=render("4.6.12-overlap",second,c2,secondary_doc,profile,{tile_policy="clipped_tiles",require_continuation=true},true)
fixtures[#fixtures+1]={name="4.6.12-overlap",origin={-0.8,-1.4},size={3.2,2.8},cells=#second.structures.tiling.cells,edges=#second.structures.tiling.edges,vertices=#second.structures.tiling.vertices}
check(first.id~=second.id and first.extensions.periodic.frame_identity==second.extensions.periodic.frame_identity,"overlap fixture did not query same frame independently")
local a,b=first.structures.tiling,second.structures.tiling
local av,ae,ac=index(a.vertices),index(a.edges),index(a.cells);local shared={vertices=0,edges=0,cells=0}
for _,v in ipairs(b.vertices)do if av[v.id]then assert(equal(av[v.id],v),"overlapping vertex data changed");shared.vertices=shared.vertices+1 end end
for _,e in ipairs(b.edges)do if ae[e.id]then
 local old=ae[e.id];assert(old.global_owner==e.global_owner and equal(old.global_cells,e.global_cells)and equal(old.midpoint,e.midpoint),"overlapping global edge changed");shared.edges=shared.edges+1
end end
for _,tile in ipairs(b.cells)do if ac[tile.id]then assert(equal(ac[tile.id],tile),"overlapping cell changed");shared.cells=shared.cells+1 end end
check(shared.vertices>100 and shared.edges>100 and shared.cells>50,"too few shared objects exercised")
local witness_doc=doc("common-world-window",{-0.8,-1.4})
local witness_opts={crop={0,0,1.8,2.8},tile_policy="clipped_tiles",require_continuation=true}
render("common-a",first,ctx(),witness_doc,profile,witness_opts,false)
render("common-b",second,ctx(),witness_doc,profile,witness_opts,false)
for _,ext in ipairs({"pdf","svg","plan"})do check(outputs["common-a."..ext]==outputs["common-b."..ext],"independent patches disagree in one identical physical viewport")end
fixtures[#fixtures+1]={name="common-a",origin={-0.8,-1.4},size={1.8,2.8},instance="4.6.12.instance"}
fixtures[#fixtures+1]={name="common-b",origin={-0.8,-1.4},size={1.8,2.8},instance="4.6.12-overlap.instance"}
local one,two
for _,tile in ipairs(a.cells)do if tile.address[1]==0 and tile.address[2]==0 then
 for i,use in ipairs(tile.boundary)do if ac[use.neighbor]then
   one=F.port(first,tile.id,i,1,3);two=F.port(first,use.neighbor,use.neighbor_edge,2,3);break
 end end
 if one then break end
end end
check(one and equal(one,two)and one.lattice_denominator==18,"two sides disagree at fractional shared port")
local m=first.extensions.periodic.matrix;local dx,dy=2*m[1]-m[3],2*m[2]-m[4]
local shifted=generate(s,doc("shifted",{-2.2+dx,-1.4+dy}),profile)
local r,t=first.extensions.periodic.integer_query,shifted.extensions.periodic.integer_query
check(t[1]==r[1]+2 and t[3]==r[3]+2 and t[2]==r[2]-1 and t[4]==r[4]-1,"translated world query has inconsistent integer extent")
local lattice={}
for _,v in ipairs(shifted.structures.tiling.vertices)do lattice[T.key(v.lattice)]=v end
for _,v in ipairs(a.vertices)do local q=assert(lattice[T.key(T.shift(v.lattice,2,-1))]);assert(math.abs(q.point[1]-v.point[1]-dx)<1e-11 and math.abs(q.point[2]-v.point[2]-dy)<1e-11,"world lattice translation changed geometry")end
check(true,"translated patch vertex geometry")
write("translated.instance",P.serialize(shifted))
local bad=P.plain(first);bad.structures.tiling.edges[1].global_owner="forged"
check(not pcall(F.validate,bad,ctx()),"forged global owner accepted")
bad=P.plain(first);bad.structures.tiling.vertices[1].point[1]=bad.structures.tiling.vertices[1].point[1]+0.001
check(not pcall(F.validate,bad,ctx()),"forged realized lattice point accepted")
local mv=P.plain(first_plan.view);mv.transform={1,0,0.15,1,0,0}
check(not pcall(P.view,mv,first,definition),"metric shear accepted")
mv.transform={-1,0,0,1,0,0};check(not pcall(P.view,mv,first,definition),"implicit reflection accepted")
check(not L.view(first,definition,primary_doc,"panel",profile,{halo=0.1,require_continuation=true},ctx()),"undersized halo accepted")
local huge=P.plain(s);huge.document.bounds={-100,-100,100,100}
local oversized,problem=registry:generate(definition.id,huge,ctx())
check(not oversized and problem.diagnostics[1]:find("1536",1,true),"oversized query did not diagnose limits")
local denied,why=registry:generate(definition.id,s,ctx(nil,{objects=0,operations=100,bytes=1000}))
check(not denied and why.code=="budget_exhausted","budget returned partial geometry")
local cancelled,stop=registry:generate(definition.id,s,ctx(nil,nil,function()return true end))
check(not cancelled and stop.status=="cancelled","cancelled query returned geometry")
local small=spec("square",0.75,0);local small_profile=F.profile(definition,0.75);local masked_doc=doc("mask",{-2.2,-1.4},true)
local mx,mc=generate(small,masked_doc,small_profile)
local full=assert(L.view(mx,definition,masked_doc,"panel",small_profile,{tile_policy="full_tiles",require_continuation=true},mc))
local clipped=assert(L.view(mx,definition,masked_doc,"panel",small_profile,{tile_policy="clipped_tiles",require_continuation=true},mc))
check(#full.decisions.selection.cell_ids>0 and #full.decisions.selection.cell_ids<#clipped.decisions.selection.cell_ids and full.source_digest==clipped.source_digest,"full versus clipped view changed source")
local runtime=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")
local environment=Q.environment({revision="working/periodic/"..digest,files={construction=bytes,style={},view={},renderer={}}},{lua=_VERSION,host=runtime},{id=Render.VERSION,version="1"})
local recipe=assert(L.recipe(definition,small,masked_doc,"panel",small_profile,{},{tile_policy="full_tiles",require_continuation=true}))
local result=Q.execute(Q.decode(Q.encode(recipe)),registry,environment)
check(result.record.status=="complete"and result.bytes.instance==P.serialize(mx),"saved planner recipe changed actual construction")
local full_drawing=Render.plan(result.scene,result.instance,result.view,definition)
write("masked-full.pdf",Render.pdf(full_drawing));write("masked-full.svg",Render.svg(full_drawing));write("masked-full.plan",P.serialize(full_drawing))
fixtures[#fixtures+1]={name="masked-full",origin={-2.2,-1.4},size={3.2,2.8}}
write("masked-full.recipe",Q.encode(recipe));write("masked-full.scene",result.bytes.scene);write("masked-full.instance",result.bytes.instance)
local report={stage="09",source_digest=digest,source=sources,checks=checks,host=runtime,runtime=_VERSION,outputs=outputs,fixtures=fixtures,shared=shared,third_port=P.plain(one),
 translated_address_delta={2,-1},translation_vector={dx,dy},recipe=P.plain(result.record),full_count=#full.decisions.selection.cell_ids,clipped_count=#clipped.decisions.selection.cell_ids}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("periodiccheck: "..checks.." checks; five certified tilings, seven groups, world overlap and ports; "..root)
