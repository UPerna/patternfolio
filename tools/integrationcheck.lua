local P,R,D,L,Q,V=require("pattern"),require("pattern_registry"),require("pattern_document"),
  require("pattern_planner"),require("pattern_recipe"),require("pattern_render")
local Parse,H,A=require("pattern_parse"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local registry=R.new()
local limits={objects=60000,operations=2000000,bytes=64*1024*1024}
local sources={}
local function read(name)
  local file=assert(io.open(name,"rb"))
  local data=file:read("*a"):gsub("\r\n","\n")
  file:close()
  return data
end
for name in fs.dir(".") do if name:match("%.lua$") then sources[name]=read(name) end end
sources["tools/integrationcheck.lua"]=read("tools/integrationcheck.lua")
sources["tools/integration_oracle.py"]=read("tools/integration_oracle.py")
local hashes={}
for name,data in pairs(sources) do hashes[name]=H.sha256(data) end
local digest=H.value("integration/source",hashes)
local root="build/integration/"..digest
for _,path in ipairs{"build","build/integration",root} do fs.mkdir(path) end
local output={}
local function write(name,data) output[name]=A.write(root.."/"..name,data) end
local env=Q.environment({revision="working/integration/"..digest,
  files={construction=sources,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=V.VERSION,version="1"})

local scaffold={vertices={},edges={}}
for i,p in ipairs{{.8,1.2},{4,.8},{4.6,3.7},{2.2,5},{.7,3.5},{2.45,2.8}} do
  scaffold.vertices[i]={id="v"..i,point=p}
end
for i,e in ipairs{{1,2},{2,3},{3,4},{4,5},{5,1},{1,6},{2,6},{3,6},{4,6},{5,6}} do
  scaffold.edges[i]={id="e"..i,from="v"..e[1],to="v"..e[2]}
end
local cases={
  {name="botanical",module="pattern_botanical_panel",seed=7,box={0,0,12,11},
    parameters={density=.6},constraints={region={unit="cm",points={{1,1},{9,1},{11,5},{8,10},{2,9}}}},
    mask={6,4,7,5.2},palette={palette="indigo"},
    invalid=function(s) s.constraints.region.points[3]={3,4} end},
  {name="celtic",module="pattern_celtic",seed=12,box={0,0,5.4,5.5},
    parameters={smoothing=1},inputs={scaffold=scaffold},palette={stroke={.52,.14,.22}},
    invalid=function(s) s.inputs.scaffold.edges[1].to="absent" end},
  {name="islamic",module="pattern_islamic",seed=11,box={-2.7,-1.8,2.7,1.8},
    parameters={scaffold="square",contact_angle=35,lattice_step=1.8},
    mask={3.3,1.58,3.8,2.1},palette={stroke={.52,.14,.22}},
    invalid=function(s) s.parameters.scaffold="absent" end},
  {name="penrose",module="pattern_penrose",seed=14,box={-2,-1.5,2.5,1.7},
    parameters={phase="amber",edge_length=.45},palette={palette="plum"},diagnostic={display="matching"},
    invalid=function(s) s.parameters.phase="absent" end},
  {name="spectre",module="pattern_spectre",seed=15,box={-1.5,-6,6.2,1.55},
    parameters={depth=2,whole_root=true,edge_length=.25},style={display="uniform"},palette={display="lineage"},
    invalid=function(s) s.parameters.boundary="absent" end},
}
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local function make_document(c)
  local b=c.box
  local w,h=b[3]-b[1],b[4]-b[2]
  local mask=c.mask and {{id="callout",role="protected_content",space="page",bounds=c.mask}} or P.array()
  local anchors=c.name=="botanical" and {{id="root",role="root",space="page",point={3,1.8}}} or P.array()
  local frame=c.name=="islamic" and "ornament/islamic-pic/global" or c.name.."/world"
  return D.new({id=c.name.."/document",unit="cm",frame={id=frame,origin={0,0}},
    twoside=false,spreads=P.array(),pages={{id="panel",number=1,size={w,h},origin={b[1],b[2]},
    trim={0,0,w,h},bleed={0,0,0,0},margins={0,0,0,0},binding_offset=0,offset={0,0},
    protected_regions=mask,anchors=anchors}}})
end
local function operations(plan)
  local geometry,refs={},{}
  for op in V.operations(plan) do
    op=P.plain(op)
    if op.paint then
      op.paint.fill=op.paint.fill and true
      op.paint.stroke=op.paint.stroke and true
      refs[op.semantic_ref]=true
    end
    geometry[#geometry+1]=H.value("integration/operation",op)
  end
  return H.value("integration/geometry",geometry),refs
end
local function annotated(scene,instance,view,definition,name)
  local data=P.plain(scene)
  local structures=instance.structures
  local function marker(ref,p,r,color)
    local x,y=p[1],p[2]
    data.operations[#data.operations+1]={op="path",semantic_ref=ref,transform=P.plain(view.transform),
      commands={{"M",x-r,y},{"L",x,y+r},{"L",x+r,y},{"L",x,y-r},{"Z"}},
      paint={fill=color,stroke={1,1,1},stroke_width=.015}}
  end
  if name=="botanical" then
    for _,node in ipairs(structures.growth.nodes) do
      if node.parent then marker(node.id,node.point,.085,{.61,.15,.27}) end
    end
  elseif name=="celtic" then
    for _,crossing in ipairs(structures.strands.crossings) do
      local left=crossing.over_branch:sub(-2)=="/L"
      marker(crossing.id,crossing.point,.07,left and {.71,.22,.13} or {.19,.52,.52})
    end
  elseif name=="islamic" then
    local points={}
    for _,vertex in ipairs(structures.graph.vertices) do points[vertex.id]=vertex.point end
    for _,contact in ipairs(instance.extensions.pic.contacts) do
      if contact.role=="interior" then marker(contact.id,assert(points[contact.id]),.052,{.71,.23,.20}) end
    end
  end
  return V.plan(P.scene(data,instance,view,definition),instance,view,definition)
end
local summaries,plans={},{}
for _,c in ipairs(cases) do
  local family=require(c.module)
  local definition=family.register(registry)
  local document=make_document(c)
  local options=c.name=="botanical" and {mode="adaptive",generation_region="media",
    construction_scale=16,density_parameter="density"} or {mode="view_only",construction_scale=2}
  local profile=L.profile(definition,options)
  local raw={id="integration/"..c.name,definition_ref={id=definition.id,version=definition.version},
    seed=c.seed,parameters=c.parameters,inputs=c.inputs or {},constraints=c.constraints or {},
    style=c.style or {},budget=limits,document={unit="cm",bounds=c.box,protected_regions=P.array()}}
  local spec=P.specification(raw,definition)
  local function recipe(design,view)
    if c.name=="islamic" then
      local x,y=c.box[1],c.box[2]
      return Q.from_specification(definition,design,{unit="cm",transform={1,0,0,1,-x,-y},
        crop=view and view.crop or {0,0,c.box[3]-x,c.box[4]-y},
        protected_regions=D.masks(D.page(document,"panel")),derived=false,validity="construction_preserved"},2)
    end
    return assert(L.recipe(definition,design,document,"panel",profile,{},view or {}))
  end
  local function execute(saved)
    local result=Q.execute(saved,registry,env)
    if result.record.status~="complete" then error(c.name..": "..P.serialize(result.record.diagnostics)) end
    return result
  end
  local function plan(result) return V.plan(result.scene,result.instance,result.view,definition) end
  check(P.serialize(P.specification(Parse.decode(P.serialize(spec)),definition))==P.serialize(spec),"spec round trip")
  local original=recipe(spec)
  local encoded=Q.encode(original)
  check(Q.encode(Q.decode(encoded))==encoded,"recipe round trip")
  local first,replay=execute(original),execute(Q.decode(encoded))
  local context=R.context({seed=c.seed,source={revision="working/integration/"..digest},
    frame=P.plain(first.instance.frame),limits=limits})
  local function planned_plan(view_options,style)
    local planned=assert(L.view(first.instance,definition,document,"panel",profile,view_options,context))
    check(planned.source_digest==H.sha256(first.bytes.instance),"planner changed source identity")
    local lowered=assert(L.lower(registry,definition.id,first.instance,definition,planned,style,context))
    return V.plan(lowered.scene,first.instance,lowered.view,definition)
  end
  if c.name=="islamic" then
    check(V.svg(planned_plan({},{}))==V.svg(plan(first)),
      "PIC document and direct view disagree")
    local open=P.plain(first.view)
    open.protected_regions=P.array()
    open=P.view(open,first.instance,definition)
    local scene=registry:lower(definition.id,first.instance,open,{},context)
    local unmasked=V.plan(scene,first.instance,open,definition)
    write("islamic-unmasked.pdf",V.pdf(unmasked))
    write("islamic-unmasked.svg",V.svg(unmasked))
  end
  check(first.bytes.instance==replay.bytes.instance and first.bytes.scene==replay.bytes.scene,"seed replay")
  check(P.serialize(P.instance(Parse.decode(first.bytes.instance),definition))==first.bytes.instance,"instance round trip")
  check(P.serialize(P.scene(Parse.decode(first.bytes.scene),first.instance,first.view,definition))==first.bytes.scene,"scene round trip")
  local edited=P.plain(spec);edited.style=c.palette
  local recolored=execute(recipe(edited))
  local base,alt=plan(first),plan(recolored)
  check(first.bytes.instance==recolored.bytes.instance and first.record.dependencies.cache.structure==
    recolored.record.dependencies.cache.structure,"palette changed construction")
  check(operations(base)==operations(alt) and V.svg(base)~=V.svg(alt),"palette did not only repaint")
  local w,h=c.box[3]-c.box[1],c.box[4]-c.box[2]
  local a=planned_plan({crop={w*.12,h*.12,w*.78,h*.78}},spec.style)
  local b=planned_plan({crop={w*.24,h*.20,w*.89,h*.89}},spec.style)
  check(P.serialize(first.instance)==first.bytes.instance,"crop mutated topology")
  local _,ar=operations(a)
  local _,br=operations(b)
  local shared=0
  for ref in pairs(ar) do if br[ref] then shared=shared+1 end end
  check(shared>0,"no common painted identities in overlapping views")
  local invalid=P.plain(spec)
  c.invalid(invalid)
  local valid,bad=pcall(recipe,invalid)
  check(not valid or Q.execute(bad,registry,env).record.status=="failed","invalid input accepted")
  write(c.name..".recipe",encoded)
  write(c.name..".instance",first.bytes.instance)
  write(c.name..".pdf",V.pdf(base));write(c.name..".svg",V.svg(base))
  local diagnostic=annotated(recolored.scene,first.instance,first.view,definition,c.name)
  if c.diagnostic then edited.style=c.diagnostic;diagnostic=plan(execute(recipe(edited))) end
  write(c.name.."-diagnostic.pdf",V.pdf(diagnostic));write(c.name.."-diagnostic.svg",V.svg(diagnostic))
  summaries[c.name]={shared_refs=shared,validator=P.plain(first.record.validation),mask=c.mask}
  plans[c.name]=base
end
local page={0,0,20,15}
local one=V.compose_vectors(page,{{plan=plans.botanical,bounds={.8,.8,9.7,14.2}},
  {plan=plans.celtic,bounds={10.3,7.65,19.2,14.2}},{plan=plans.islamic,bounds={10.3,.8,19.2,7.35}}})
local two=V.compose_vectors(page,{{plan=plans.penrose,bounds={.8,7.65,19.2,14.2}},
  {plan=plans.spectre,bounds={.8,.8,19.2,7.35}}})
write("composition.pdf",V.pdf_document({one,two}))
write("composition-1.svg",V.svg(one));write("composition-2.svg",V.svg(two))
A.write(root.."/receipt.json",P.serialize({stage="16",source_digest=digest,checks=checks,outputs=output,families=summaries}))
print("Five-family integration checks: "..checks)
