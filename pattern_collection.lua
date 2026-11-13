local P,H,G,V=require("pattern"),require("pattern_hash"),require("pattern_geometry"),require("pattern_render")
local M={VERSION="original-collection-v1"}
local identity={1,0,0,1,0,0}

local function complete_text(plan)
  if #plan.text==0 then return end
  local text_refs={}
  for _,text in ipairs(plan.text) do text_refs[text.semantic_ref]=true end
  local depth=0
  for op in V.operations(plan) do
    if op.op=="push_clip" then depth=depth+1
    elseif op.op=="pop_clip" then depth=depth-1
    elseif text_refs[op.semantic_ref] then
      assert(depth==1,"collection-text-requires-unmasked-plan")
    end
  end
  local fonts={}
  for _,f in ipairs(plan.fonts) do
    local glyphs={}
    for _,g in ipairs(f.glyphs) do glyphs[g.id]=g end
    fonts[f.id]={units=f.units_per_em,glyphs=glyphs}
  end
  for _,text in ipairs(plan.text) do
    local f=assert(fonts[text.font_ref],"collection-text-font")
    for _,g in ipairs(text.glyphs) do
      local b=assert(f.glyphs[g.glyph_ref],"collection-text-glyph").bounds
      local k=text.size/f.units
      local angle=g.rotation or 0
      local c,s=math.cos(angle),math.sin(angle)
      local m=G.compose(text.transform or identity,{c*k,s*k,-s*k,c*k,
        text.origin[1]+g.offset[1],text.origin[2]+g.offset[2]})
      for _,p in ipairs({{b[1],b[2]},{b[3],b[2]},{b[3],b[4]},{b[1],b[4]}}) do
        local q=G.transform(p,m)
        assert(q[1]>=plan.bounds[1]-1e-9 and q[1]<=plan.bounds[3]+1e-9
          and q[2]>=plan.bounds[2]-1e-9 and q[2]<=plan.bounds[4]+1e-9,"collection-clipped-text")
      end
    end
  end
end

function M.palette(plan,options)
  for k in pairs(options) do assert(k=="ink" or k=="accent" or k=="intensity","collection-palette-option:"..k) end
  local intensity=options.intensity or 1
  assert(type(intensity)=="number" and intensity>=0 and intensity<=1,"collection-intensity-range")
  local out=P.plain(plan)
  local operations=P.array()
  for operation in V.operations(plan) do
    local op=P.plain(operation)
    if op.paint then
      for _,key in ipairs({"fill","stroke"}) do
        local color=op.paint[key]
        if color then
          assert(not op.paint.color_space or op.paint.color_space=="rgb","collection-rgb-required")
          local base=(color[1]>color[3] and options.accent or options.ink)
          assert(type(base)=="table" and #base==3,"collection-palette-rgb")
          local shade=.16+.65*(.2126*color[1]+.7152*color[2]+.0722*color[3])
          local result={}
          for i=1,3 do
            assert(base[i]>=0 and base[i]<=1,"collection-palette-range")
            result[i]=1-intensity*(1-base[i])*(1-shade)
          end
          op.paint[key]=result
        end
      end
    end
    operations[#operations+1]=op
  end
  out.operations=operations
  out.operation_segments=nil
  out.operation_count=nil
  return P.snapshot(out)
end

-- Outline paths and logical text undergo the same positive uniform placement.
function M.page(bounds,panels)
  assert(#panels>0 and #panels<=32,"collection-panel-count")
  local vectors,logical,fonts,order=P.array(),P.array(),{},P.array()
  local ids={}
  for _,panel in ipairs(panels) do
    assert(type(panel.id)=="string" and not ids[panel.id],"collection-panel-identity")
    ids[panel.id]=true
    complete_text(panel.plan)
    local plan=P.plain(panel.plan)
    local b,slot=plan.bounds,panel.bounds
    local scale=math.min((slot[3]-slot[1])/(b[3]-b[1]),(slot[4]-slot[2])/(b[4]-b[2]))
    assert(scale>0,"collection-positive-placement")
    local m={scale,0,0,scale,(slot[1]+slot[3]-scale*(b[1]+b[3]))/2,
      (slot[2]+slot[4]-scale*(b[2]+b[4]))/2}
    for _,font in ipairs(plan.fonts) do
      assert(not fonts[font.id] or P.serialize(fonts[font.id])==P.serialize(font),"collection-font-collision")
      fonts[font.id]=font
    end
    for _,text in ipairs(plan.text) do
      text.semantic_ref=panel.id.."/"..text.semantic_ref
      text.transform=G.compose(m,text.transform or identity)
      logical[#logical+1]=text
      order[#order+1]=text.semantic_ref
    end
    local ops=P.array()
    for operation in V.operations(panel.plan) do
      local op=P.plain(operation)
      if op.semantic_ref then op.semantic_ref=panel.id.."/"..op.semantic_ref end
      ops[#ops+1]=op
    end
    plan.operations=ops
    plan.operation_segments=nil
    plan.operation_count=nil
    plan.text=P.array()
    plan.reading_order=P.array()
    plan.fonts=P.array()
    vectors[#vectors+1]={plan=plan,bounds=slot}
  end
  local out=P.plain(V.compose_vectors(bounds,vectors))
  out.text,out.reading_order=logical,order
  local names={}
  for id in pairs(fonts) do names[#names+1]=id end
  table.sort(names,P.byte_less)
  out.fonts=P.array()
  for _,id in ipairs(names) do out.fonts[#out.fonts+1]=fonts[id] end
  return P.snapshot(out)
end

local function polygon(cell,edges,vertices,convex)
  local ring={}
  for _,use in ipairs(cell.boundary) do
    local edge=assert(edges[use.edge],"collection-missing-edge")
    ring[#ring+1]=assert(vertices[use.reversed and edge.to or edge.from],"collection-missing-vertex")
  end
  local center={0,0}
  for _,p in ipairs(ring) do center[1]=center[1]+p[1]/#ring;center[2]=center[2]+p[2]/#ring end
  if convex then
    for i,a in ipairs(ring) do
      local b=ring[i%#ring+1]
      for j,p in ipairs(ring) do
        if j~=i and j~=i%#ring+1 then
          assert(require("pattern_predicates").orient2d(a,b,p)>0,"collection-strictly-convex-ccw-cell")
        end
      end
    end
  end
  return center
end

-- A typed decoration overlay retains the certified tiling and global frame.
-- Each edge supplies one midpoint port, with opposite inward normal tangents.
function M.decorate(instance,view,definition,scene,color)
  local before=P.serialize(instance)
  local t=assert(instance.structures.tiling,"collection-tiling-required")
  local vertices,edges={},{}
  for _,v in ipairs(t.vertices) do vertices[v.id]=v.point end
  for _,e in ipairs(t.edges) do edges[e.id]=e end
  local out=P.plain(scene)
  local ports,centers=P.array(),P.array()
  local owners={}
  for _,cell in ipairs(t.cells) do
    local center=polygon(cell,edges,vertices,true)
    centers[#centers+1]={cell=cell.id,point=center,chirality=cell.chirality}
    for _,use in ipairs(cell.boundary) do
      local edge=edges[use.edge]
      local a,b=vertices[edge.from],vertices[edge.to]
      local dx,dy=b[1]-a[1],b[2]-a[2]
      local length=math.sqrt(dx*dx+dy*dy)
      assert(length>.01,"collection-port-edge-length")
      local sign=use.reversed and -1 or 1
      local normal={-sign*dy/length,sign*dx/length}
      local midpoint={(a[1]+b[1])/2,(a[2]+b[2])/2}
      local h=(center[1]-midpoint[1])*normal[1]+(center[2]-midpoint[2])*normal[2]
      assert(h>0,"collection-port-interior")
      local p={edge=edge.id,cell=cell.id,point=midpoint,inward=normal,
        width_cm=.012,kind="normal-tangent-motif",frame=instance.frame.id}
      local prior=owners[edge.id]
      if prior then
        assert(not prior.paired and prior.cell~=cell.id,"collection-port-incidence")
        assert(P.serialize(prior.point)==P.serialize(midpoint) and prior.inward[1]==-normal[1]
          and prior.inward[2]==-normal[2],"collection-shared-edge-port")
        prior.paired=true
        p.paired=true
      else owners[edge.id]=p end
      ports[#ports+1]=p
      out.operations[#out.operations+1]={op="path",semantic_ref=cell.id,transform=P.plain(view.transform),
        commands={{"M",midpoint[1],midpoint[2]},
          {"C",midpoint[1]+normal[1]*h*.6,midpoint[2]+normal[2]*h*.6,
            center[1]*.85+midpoint[1]*.15,center[2]*.85+midpoint[2]*.15,center[1],center[2]}},
        paint={stroke=color,stroke_width=.012,cap="round"}}
    end
  end
  assert(P.serialize(instance)==before,"collection-decoration-mutated-tiling")
  return P.scene(out,instance,view,definition),P.snapshot({source_sha256=H.sha256(before),
    kind="cell-compass-stars-v1",ports=ports,centers=centers,frame=P.plain(instance.frame)})
end

function M.detail(registry,definition,instance,view,style,context)
  local before=P.serialize(instance)
  local scene=registry:lower(definition.id,instance,view,style,context)
  local out=P.plain(scene)
  local annotations=P.array()
  local t=assert(instance.structures.tiling,"collection-detail-tiling-required")
  assert(t.hierarchy and #t.hierarchy>0,"collection-detail-hierarchy-required")
  local vertices,edges={},{}
  local centers={}
  for _,v in ipairs(t.vertices) do vertices[v.id]=v.point end
  for _,e in ipairs(t.edges) do edges[e.id]=e end
  for _,cell in ipairs(t.cells) do
    local center=polygon(cell,edges,vertices,false)
    centers[cell.id]=center
    local r=.035
    out.operations[#out.operations+1]={op="path",semantic_ref=cell.id,transform=P.plain(view.transform),
      commands={{"M",center[1]-r,center[2]},{"L",center[1]+r,center[2]},
        {"M",center[1],center[2]-r},{"L",center[1],center[2]+r}},
      paint={stroke={.55,.20,.15},stroke_width=.008}}
    annotations[#annotations+1]={ref=cell.id,point=center,prototype=cell.prototype,
      chirality=cell.chirality,parent=cell.parent,lineage_label=cell.lineage_label}
  end
  local nodes={}
  for _,node in ipairs(t.hierarchy) do nodes[node.id]=node end
  local active={}
  local function center(id)
    if centers[id] then return centers[id] end
    assert(not active[id],"collection-hierarchy-cycle")
    active[id]=true
    local node=assert(nodes[id],"collection-hierarchy-child")
    assert(#node.children>0,"collection-hierarchy-empty")
    local p={0,0}
    for _,child in ipairs(node.children) do
      local q=center(child)
      p[1],p[2]=p[1]+q[1]/#node.children,p[2]+q[2]/#node.children
    end
    centers[id]=p
    active[id]=nil
    return p
  end
  local groups=P.array()
  for _,node in ipairs(t.hierarchy) do
    local p=center(node.id)
    groups[#groups+1]={ref=node.id,point=p,children=P.plain(node.children),level=node.level,parent=node.parent}
    local commands=P.array()
    for _,child in ipairs(node.children) do
      local q=center(child)
      commands[#commands+1]={"M",p[1],p[2]}
      commands[#commands+1]={"L",q[1],q[2]}
    end
    local r=.04+.025*node.level
    commands[#commands+1]={"M",p[1]-r,p[2]}
    commands[#commands+1]={"L",p[1],p[2]+r}
    commands[#commands+1]={"L",p[1]+r,p[2]}
    commands[#commands+1]={"L",p[1],p[2]-r}
    commands[#commands+1]={"Z"}
    out.operations[#out.operations+1]={op="path",semantic_ref=node.id,transform=P.plain(view.transform),
      commands=commands,paint={stroke={.55,.20,.15},stroke_width=.008,dash={array={.04,.03},phase=0}}}
  end
  assert(P.serialize(instance)==before,"collection-detail-mutated-source")
  return P.scene(out,instance,view,definition),P.snapshot({source_sha256=H.sha256(before),
    annotations=annotations,groups=groups,hierarchy=P.plain(t.hierarchy),view_sha256=H.value("collection/view",view)})
end

function M.compatibility(options)
  for k in pairs(options) do
    assert(k=="density" or k=="intensity" or k=="theme" or k=="ornament","collection-unsupported-control:"..k)
  end
  local density=options.density
  if density~=nil then density=require("layout").resolve({density=density}).density end
  local intensity=options.intensity or 1
  assert(type(intensity)=="number" and intensity>=0 and intensity<=1,"collection-intensity-range")
  assert(options.theme==nil or options.theme=="botanical" or options.theme=="compass","collection-unsupported-theme")
  assert(options.ornament==nil or options.ornament=="leaf" or options.ornament=="flower" or options.ornament=="divider",
    "collection-unsupported-ornament")
  return {legacy_density=density,intensity=intensity,theme=options.theme or "botanical",ornament=options.ornament}
end

function M.legacy_geometry(geometry,options)
  local controls=M.compatibility(options)
  assert(controls.theme=="botanical" and controls.ornament==nil and options.intensity==nil,
    "collection-legacy-control-scope")
  local out=P.plain(geometry)
  local layout=P.plain(out.layout or {})
  if controls.legacy_density then layout.density=controls.legacy_density end
  out.layout=require("layout").resolve(layout)
  return out
end

function M.controlled_plan(result,definition,options,palette)
  local controls=M.compatibility(options)
  assert(controls.legacy_density==nil and controls.ornament==nil,
    "collection-density-is-generation-and-inline-needs-asset-recipe")
  local scene=result.scene
  if controls.theme=="compass" then
    scene=M.decorate(result.instance,result.view,definition,scene,{.98,.94,.84})
  else
    assert(result.instance.structures.growth or result.instance.structures.strands,
      "collection-botanical-theme-requires-declared-growth-or-hybrid")
  end
  local colors=P.plain(palette)
  colors.intensity=controls.intensity
  return M.palette(V.plan(scene,result.instance,result.view,definition),colors)
end

function M.inline(kind,size,seed,angle)
  assert(kind=="leaf" or kind=="flower" or kind=="divider","collection-unsupported-ornament")
  assert(type(angle)=="number" and math.abs(angle)<=180,"collection-inline-angle")
  local d=require("pattern_collection_assets").definition()
  local radians=angle*math.pi/180
  local a,b=math.cos(radians),math.sin(radians)
  return require("pattern_recipe").from_specification(d,{
    id="collection/inline-"..kind,definition_ref={id=d.id,version=d.version},seed=seed,
    parameters={size=size},inputs={kind=kind},style={},constraints={},
    budget={objects=70000,operations=4000000,bytes=64*1024*1024},
    document={unit="cm",bounds={0,0,4,4},protected_regions=P.array()}},
    {unit="cm",transform={a,b,-b,a,2-2*a+2*b,2-2*b-2*a},crop={0,0,4,4},
      protected_regions=P.array(),derived=false,validity="construction_preserved"},2)
end

function M.record(members,products)
  local out={schema="florilegium-original-collection@1",version=M.VERSION,
    members=P.array(),products=P.plain(products)}
  local ids={}
  for _,member in ipairs(members) do
    assert(type(member.id)=="string" and #member.id<=64 and member.id:match("^[%w_-]+$")
      and not ids[member.id],"collection-member-id")
    ids[member.id]=true
    local encoded=require("pattern_recipe").encode(member.recipe)
    out.members[#out.members+1]={id=member.id,recipe_file=member.id..".recipe",recipe_sha256=H.sha256(encoded),
      instance_file=member.id..".instance",instance_sha256=H.sha256(P.serialize(member.instance)),
      validation=P.plain(member.validation)}
  end
  return P.serialize(out)
end

function M.replay(bytes,registry,environment,resolve)
  assert(type(resolve)=="function","collection-data-resolver-required")
  local data=require("pattern_parse").decode(bytes)
  assert(data.schema=="florilegium-original-collection@1" and data.version==M.VERSION,
    "collection-record-version")
  local results,plans={},{}
  local Q,R=require("pattern_recipe"),require("pattern_registry")
  for _,member in ipairs(data.members) do
    assert(type(member.id)=="string" and #member.id<=64 and member.id:match("^[%w_-]+$")
      and member.recipe_file==member.id..".recipe" and member.instance_file==member.id..".instance",
      "collection-member-file")
    local recipe,instance=resolve(member.recipe_file),resolve(member.instance_file)
    assert(not results[member.id] and H.sha256(recipe)==member.recipe_sha256
      and H.sha256(instance)==member.instance_sha256,"collection-member-integrity")
    local result=Q.execute(Q.decode(recipe),registry,environment)
    assert(result.record.status=="complete" and result.bytes.instance==instance,"collection-member-replay")
    results[member.id]=result
  end
  for _,render in ipairs(data.products.renders) do
    assert(not plans[render.id],"collection-render-id")
    local result=assert(results[render.member],"collection-render-member")
    local definition=registry:definition(result.instance.definition_ref.id)
    local view=render.view and P.view(render.view,result.instance,definition) or result.view
    local context=R.context({seed=result.instance.provenance.seed,source={revision="collection/replay"},
      frame=P.plain(result.instance.frame),limits={objects=70000,operations=4000000,bytes=64*1024*1024}})
    local scene=registry:lower(definition.id,result.instance,view,render.style or {},context)
    if render.overlay=="ports" then
      scene=M.decorate(result.instance,view,definition,scene,{.98,.94,.84})
    elseif render.overlay=="detail" then
      scene=M.detail(registry,definition,result.instance,view,render.style or {},context)
    else assert(render.overlay==nil,"collection-overlay-kind") end
    plans[render.id]=M.palette(V.plan(scene,result.instance,view,definition),data.products.palette)
  end
  local pages=P.array()
  for _,page in ipairs(data.products.pages) do
    local panels=P.array()
    for _,p in ipairs(page.panels) do
      panels[#panels+1]={id=p.id,plan=assert(plans[p.render_ref],"collection-page-render"),bounds=p.bounds}
    end
    pages[#pages+1]=M.page(page.bounds,panels)
  end
  return {plans=plans,pages=pages}
end

return M
