local P,R,Q,V=require("pattern"),require("pattern_registry"),require("pattern_recipe"),require("pattern_render")
local C,H,A=require("pattern_collection"),require("pattern_hash"),require("pattern_artifact")
local Parse,fs=require("pattern_parse"),require("lfs")
local reg=R.new()
local assets=require("pattern_collection_assets").register(reg)
local knot=require("pattern_celtic").register(reg)
local tiling=require("pattern_penrose").register(reg)
local spectre=require("pattern_spectre").register(reg)
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local s=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name],hashes[name]=s,H.sha256(s)
  return s
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
read("tools/collectioncheck.lua")
read("tools/collection_oracle.py")
local font=Parse.decode(read("docs/validation/fixtures/micrography-font.json"))
local digest=H.value("collection/source",hashes)
local folder="build/collection/"..digest..(PATTERN_TEST_VARIANT or "")
for _,p in ipairs{"build","build/collection",folder} do fs.mkdir(p) end
local outputs={}
local function write(name,data) outputs[name]=A.write(folder.."/"..name,data) end
local env=Q.environment({revision="working/collection/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},{id=V.VERSION,version="1"})
local palette={ink={.10,.24,.32},accent={.62,.32,.16},intensity=.9}
local members,checks=P.array(),0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local function reject(fn,why)
  local ok=pcall(fn)
  check(not ok,why)
end
local limits={objects=70000,operations=4000000,bytes=64*1024*1024}
local function build(name,d,params,inputs,box,style)
  local q=Q.from_specification(d,{id="collection/"..name,definition_ref={id=d.id,version=d.version},seed=27,
    parameters=params,inputs=inputs,constraints={},style=style or {},budget=limits,
    document={unit="cm",bounds=box,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=box,protected_regions=P.array(),
      derived=false,validity="construction_preserved"},2)
  local a=Q.execute(Q.decode(Q.encode(q)),reg,env)
  check(a.record.status=="complete",P.serialize(a.record.diagnostics))
  local b=Q.execute(Q.decode(Q.encode(q)),reg,env)
  check(a.bytes.instance==b.bytes.instance and a.bytes.scene==b.bytes.scene,"recipe replay")
  members[#members+1]={id=name,recipe=q,instance=a.instance,validation=a.record.validation}
  write(name..".recipe",Q.encode(q))
  write(name..".instance",a.bytes.instance)
  return a
end
local function plan(r,d) return C.palette(V.plan(r.scene,r.instance,r.view,d),palette) end
local function export(name,p)
  write(name..".pdf",V.pdf(p));write(name..".svg",V.svg(p))
end
local function asset(name,kind,text,size)
  return build(name,assets,{size=size or 1},{kind=kind,text=text,font=#text>0 and font or nil},{0,0,4,4})
end
local initial=asset("initial","initial","A",1.5)
local folio=asset("folio","folio","I",.9)
local folio2=asset("folio-two","folio","II",.9)
local divider=asset("divider","divider","",.9)
local leaf=asset("leaf","leaf","",.9)
local flower=asset("flower","flower","",.6)
local clipped=P.plain(plan(initial,assets))
clipped.bounds={0,0,.1,.1}
reject(function() C.page({0,0,4,4},{{id="clipped",plan=clipped,bounds={0,0,4,4}}}) end,"clipped text")
local scaffold={vertices={{id="v1",point={1,1}},{id="v2",point={4,1}},{id="v3",point={2.8,3.9}}},
  edges={{id="e1",from="v1",to="v2"},{id="e2",from="v2",to="v3"},{id="e3",from="v3",to="v1"}},
  open_sectors={{vertex="v3",edge="e2"}},botanical_port="port/v3/e2/1"}
local hybrid=build("hybrid",knot,{smoothing=1},{scaffold=scaffold},{0,0,6,6},{width=.075,stroke=palette.ink})
check(hybrid.instance.extensions.celtic.attachment.port==scaffold.botanical_port,"hybrid port")
export("hybrid",plan(hybrid,knot))
local bare=build("penrose",tiling,{phase="amber",edge_length=.52},{},{-4,-.5,4,.5})
local decorated,ports=C.decorate(bare.instance,bare.view,tiling,bare.scene,{.98,.94,.84})
check(P.serialize(bare.instance)==bare.bytes.instance,"decoration structural bytes")
write("ports.json",P.serialize(ports))
local decorated_plan=C.palette(V.plan(decorated,bare.instance,bare.view,tiling),palette)
check(V.svg(C.controlled_plan(bare,tiling,{theme="compass",intensity=.9},palette))==V.svg(decorated_plan),
  "compass theme mapping")
export("decorated",decorated_plan)
local hierarchical=build("spectre",spectre,{depth=2,whole_root=true,edge_length=.25},{},
  {-1.5,-6,6.2,1.55},{display="lineage"})
local ctx=R.context({seed=27,source={revision=digest},frame=P.plain(hierarchical.instance.frame),limits=limits})
local v=P.plain(hierarchical.view)
v.id=v.id.."/detail"
v.transform={1.5,0,0,1.5,1.5,9}
v.crop={0,0,9,10.5}
v=P.view(v,hierarchical.instance,spectre)
local annotated,annotations=C.detail(reg,spectre,hierarchical.instance,v,{display="lineage",stroke_width=.009},ctx)
write("detail.json",P.serialize(annotations))
write("detail.view",P.serialize(v))
export("detail",C.palette(V.plan(annotated,hierarchical.instance,v,spectre),palette))
check(P.serialize(hierarchical.instance)==hierarchical.bytes.instance,"zoom changed structure")
local pages,page_specs=P.array(),P.array()
local render_specs=P.array()
for _,name in ipairs({"initial","folio","folio-two","divider","leaf","flower"}) do
  render_specs[#render_specs+1]={id=name,member=name}
end
render_specs[#render_specs+1]={id="hybrid",member="hybrid",style={width=.075,stroke=palette.ink}}
render_specs[#render_specs+1]={id="decorated",member="penrose",overlay="ports"}
render_specs[#render_specs+1]={id="detail",member="spectre",overlay="detail",view=P.plain(v),
  style={display="lineage",stroke_width=.009}}
for index=1,2 do
  local vf=P.plain(bare.view)
  vf.id=vf.id.."/spread/"..index
  vf.crop=index==1 and {-4,-.5,0,.5} or {0,-.5,4,.5}
  vf=P.view(vf,bare.instance,tiling)
  local s=reg:lower(tiling.id,bare.instance,vf,{},ctx)
  local ds=C.decorate(bare.instance,vf,tiling,s,{.98,.94,.84})
  local side=C.palette(V.plan(ds,bare.instance,vf,tiling),palette)
  render_specs[#render_specs+1]={id="spread-"..index,member="penrose",view=P.plain(vf),overlay="ports"}
  local panels={
    {id="margin",plan=plan(hybrid,knot),bounds={.5,6,4.8,17}},
    {id="initial",plan=plan(initial,assets),bounds={4.5,14,8.2,17.7}},
    {id="divider",plan=plan(divider,assets),bounds={5.3,11,15.3,13.3}},
    {id="folio",plan=plan(index==1 and folio or folio2,assets),bounds={7.1,.5,8.9,2.3}},
    {id="spread",plan=side,bounds=index==1 and {.5,2.8,16,6.675} or {0,2.8,15.5,6.675}},
    {id="inline",plan=plan(index==1 and leaf or flower,assets),bounds={13.6,15.1,15.2,16.7}}}
  pages[index]=C.page({0,0,16,20},panels)
  local placement=P.array()
  local refs={"hybrid","initial","divider",index==1 and "folio" or "folio-two","spread-"..index,
    index==1 and "leaf" or "flower"}
  for i,p in ipairs(panels) do placement[i]={id=p.id,render_ref=refs[i],bounds=p.bounds} end
  page_specs[index]={bounds={0,0,16,20},panels=placement}
  export("collection-"..index,pages[index])
end
write("collection.pdf",V.pdf_document(pages))
local controls=C.compatibility({theme="compass",density="balanced",intensity=.9,ornament="divider"})
check(controls.legacy_density==.6 and controls.intensity==.9,"control mapping")
local geometry=C.legacy_geometry({seed=27,layout={style="quiet"}},{density="balanced"})
check(geometry.layout.density==.6 and geometry.layout.style=="quiet","legacy geometry mapping")
reject(function() C.legacy_geometry({},{intensity=.5}) end,"paint control on geometry packet")
local inline=Q.execute(C.inline("leaf",.9,27,15),reg,env)
check(inline.record.status=="complete",P.serialize(inline.record.diagnostics))
export("inline",C.controlled_plan(inline,assets,{intensity=.7},palette))
reject(function() C.controlled_plan(hybrid,knot,{theme="compass"},palette) end,"incompatible theme")
for _,options in ipairs{{density=.1},{theme="math"},{ornament="unsupported"},{intensity=2},{unknown=true}} do
  reject(function() C.compatibility(options) end,"unsupported compatibility")
end
local summary={schema="original-products@1",palette=palette,scale_hierarchy={page_cm={16,20},initial_cm=1.5,
  folio_cm=.9,stroke_cm=.075},controls=controls,products={
    collection={pages=2,roles={"margin","initial","divider","folio","spread","inline"}},
    hybrid={port=scaffold.botanical_port,instance_sha256=H.sha256(hybrid.bytes.instance)},
    decorated={source_sha256=H.sha256(bare.bytes.instance),ports=#ports.ports},
    detail={source_sha256=H.sha256(hierarchical.bytes.instance),annotations=#annotations.annotations,
      groups=#annotations.groups}}}
local record=C.record(members,{palette=palette,renders=render_specs,pages=page_specs,summary=summary})
write("original-collection.json",record)
local malicious=Parse.decode(record)
malicious.members[1].recipe_file="../outside.recipe"
local resolved=false
reject(function()
  C.replay(P.serialize(malicious),reg,env,function() resolved=true end)
end,"unsafe member path")
check(not resolved,"unsafe member path reached resolver")
local replay=C.replay(record,reg,env,function(name)
  local f=assert(io.open(folder.."/"..name,"rb"))
  local data=f:read("*a");f:close()
  return data
end)
check(V.pdf_document(replay.pages)==V.pdf_document(pages),"collection layout replay")
check(V.svg(replay.plans.hybrid)==V.svg(plan(hybrid,knot)),"hybrid replay")
check(V.svg(replay.plans.decorated)==V.svg(decorated_plan),"decorated replay")
check(V.svg(replay.plans.detail)==V.svg(C.palette(V.plan(annotated,hierarchical.instance,v,spectre),palette)),"detail replay")
write("summary.json",P.serialize(summary))
write("receipt.json",P.serialize({source_digest=digest,checks=checks,outputs=outputs}))
print("Collection acceptance checks",checks)
