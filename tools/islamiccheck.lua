local P,R,E,D=require("pattern"),require("pattern_registry"),require("pattern_examples"),require("pattern_document")
local I,L=require("pattern_islamic"),require("pattern_planner")
local A,H,V=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs")
local names={"tools/islamiccheck.lua","tools/islamic_oracle.py"}
for n in fs.dir(".") do if n:match("%.lua$") then names[#names+1]=n end end
table.sort(names,P.byte_less)
local source={}
for _,n in ipairs(names) do
  local f=assert(io.open(n,"rb"))
  source[#source+1]={path=n,sha256=H.sha256(f:read("*a"):gsub("\r\n","\n"))};f:close()
end
local digest=H.sha256(P.serialize(source))
local root="build/islamic/"..digest
for _,d in ipairs{"build","build/islamic",root} do fs.mkdir(d) end
local outputs={}
local function write(n,data) outputs[n]=A.write(root.."/"..n,data) end
local registry=R.new()
local definition=I.register(registry)
local frame={id="pic/world",dimension=2,unit="cm",handedness="right",origin={0,0}}
local limits={objects=60000,operations=400000,bytes=32*1024*1024}
local function context()
  return R.context({seed=11,frame=frame,limits=limits,source={revision="working/pic/"..digest}})
end
local function build(name,parameters)
  local spec=P.specification({id="fixture/"..name,definition_ref={id=definition.id,version=definition.version},
    seed=11,parameters=parameters,inputs={},constraints={},style={},budget=limits,
    document={unit="cm",bounds={-1.5,-1.2,1.5,1.2},protected_regions=P.array()}},definition)
  return registry:generate(definition.id,spec,context())
end
local function render(name,x,crop)
  local view=E.view(x,definition,crop)
  local scene=registry:lower(definition.id,x,view,{stroke_width=.026},context())
  local plan=V.plan(scene,x,view,definition)
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
  return #scene.operations
end
local function render_border(x)
  local page={id="border",number=1,size={2.8,.84},origin={-1.4,-.42},trim={0,0,2.8,.84},
    bleed={0,0,0,0},margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions=P.array()}
  local document=D.new({id="pic-border",unit="cm",frame={id=frame.id,origin=frame.origin},
    twoside=false,spreads=P.array(),pages={page}})
  local profile=L.profile(definition,{mode="view_only",construction_scale=1.8})
  local c=context()
  local planned,e=L.view(x,definition,document,page.id,profile,{},c)
  assert(planned,e and P.serialize(e))
  local lowered,err=L.lower(registry,definition.id,x,definition,planned,{stroke_width=.026},c)
  assert(lowered,err and P.serialize(err))
  local plan=V.plan(lowered.scene,x,lowered.view,definition)
  write("border.pdf",V.pdf(plan));write("border.svg",V.svg(plan))
  write("border-view.json",P.serialize(lowered.view))
  assert(planned.decisions.topology_unchanged and planned.source_digest==H.sha256(P.serialize(x)),
    "border view changed PIC construction")
  return #lowered.scene.operations
end

local function eq(a,b) return P.serialize(a)==P.serialize(b) end
local checks=0
local function check(b,why) assert(b,why);checks=checks+1 end
local fixtures={
  {"square",{scaffold="square",contact_angle=35,lattice_step=1.8}},
  {"hexagonal",{scaffold="hexagonal",contact_angle=60,lattice_step=1.8,rotation=9}},
  {"mixed",{scaffold="4.6.12",contact_angle=60,lattice_step=1.8}},
  {"displaced",{scaffold="4.8.8",contact_angle=45,lattice_step=1.8,displacement=.10}},
  {"rosette",{scaffold="4.8.8",contact_angle=45,lattice_step=1.8,rosette_ratio=1}},
  {"parquet",{scaffold="square",contact_angle=42,lattice_step=1.8,parquet_gradient=1.5}},
}
local summaries={}
for _,f in ipairs(fixtures) do
  local n,a=f[1],f[2]
  local result,err=build(n,a)
  assert(result,err and P.serialize(err))
  local x=result.instance;local k=x.extensions.pic
  write(n..".instance",P.serialize(x))
  local count=render(n,x,{-1.4,-1.1,1.4,1.1})
  check(count>0,n.." has no visible ornament")
  local n_internal=0
  for _,p in ipairs(k.contacts) do if p.role=="interior" then n_internal=n_internal+1 end end
  check(n_internal>0,n.." has no shared contacts")
  summaries[n]={faces=#k.scaffold_faces,interior_contacts=n_internal,links=#x.structures.graph.edges,paint=count}
  if n=="square" then
    local border=render_border(x)
    check(border>0 and border<count,"document border crop did not reduce paint")
    local raw=P.plain(x);raw.extensions.pic.contacts[1].angle=19
    local ok,e=pcall(I.validate,raw)
    check(not ok and tostring(e):find("pic-contact-reconstruction",1,true),"bad contact accepted")
  end
end
for _,a in ipairs{1,89} do
  local x,e=build("extreme",{scaffold="square",contact_angle=a,lattice_step=1.8})
  check(x or P.serialize(e):find("pic-unmatched-ray",1,true),"unclassified angle extreme")
end
local cases={
  {{scaffold="4.8.8",contact_angle=30,lattice_step=1.8,rosette_ratio=1},"pic-unmatched-ray"},
  {{scaffold="square",contact_angle=45,lattice_step=1.8,displacement=1.8},"pic-displacement-reaches-edge-end"},
  {{scaffold="square",contact_angle=45,lattice_step=1.8,rosette_ratio=1},"pic-rosette-requires-4.8.8"},
}
for _,case in ipairs(cases) do
  local r,e=build("reject",case[1])
  check(not r and P.serialize(e):find(case[2],1,true),"missing diagnostic "..case[2])
end
local reference
for _,scale in ipairs{.25,1,20} do
  local patch={{0,0},{scale,0},{scale,scale},{0,scale}}
  local m=I.motif(patch,37,scale*.04)
  local pairs={}
  for _,x in ipairs(m.paths) do pairs[#pairs+1]={x.first,x.second} end
  if reference then check(eq(reference,pairs),"scale changed pairing") else reference=pairs end
end
local ok_degenerate,problem=pcall(I.motif,{{0,0},{1,0},{2,0},{0,1}},45,0)
check(not ok_degenerate and tostring(problem):find("pic-strict-convex-ccw",1,true),"degenerate polygon accepted")
local irregular={{0,0},{2,0},{2.1,1},{.3,1.2}}
local copied={39,39,44,44}
local ok,motif=pcall(I.motif,irregular,42,0,function(i)return copied[i] end)
check(ok and #motif.paths==4,"irregular gap inference did not pair: "..tostring(motif))
write("gap.json",P.serialize({polygon=irregular,angles=copied,motif=motif}))
local report={stage="11",source_digest=digest,source=source,checks=checks,fixtures=summaries,outputs=outputs,runtime=_VERSION,
  host=PATTERN_TEST_HOST or "texlua"}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("islamiccheck: "..checks.." checks; source "..digest)
