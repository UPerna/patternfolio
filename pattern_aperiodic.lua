-- Finite aperiodic construction routes with an exact integer substitution fixture.
local P=require("pattern")
local H=require("pattern_hash")
local M={VERSION="finite-construction-v1"}
local routes={
  hierarchical_substitution="fixed root, local dissection, hierarchical addresses",
  projection_multigrid="basis, window/phase, certified finite enumeration",
  bounded_constraint="finite domain, hypotheses, solver and verification",
}
function M.route_registry()
  local providers={}
  return {
    register=function(name,provider)
      assert(routes[name] and not providers[name],"aperiodic-route-registration")
      assert(type(provider)=="table" and type(provider.construct)=="function" and type(provider.validate)=="function",
        "aperiodic-route-provider")
      providers[name]=provider
    end,
    construct=function(name,request,context)
      assert(routes[name],"aperiodic-unknown-route:"..tostring(name))
      local provider=assert(providers[name],"aperiodic-route-unimplemented:"..name)
      local result=provider.construct(request,context)
      assert(provider.validate(result,request)==true,"aperiodic-route-validation")
      return result
    end,
    capabilities=function()
      local out={}
      for name,contract in pairs(routes) do out[name]={contract=contract,implemented=providers[name]~=nil} end
      return P.snapshot(out)
    end,
  }
end

local occupied={{0,0},{1,0},{0,1}}
local outline={{0,0},{1,0},{2,0},{2,1},{1,1},{1,2},{0,2},{0,1}}
local labels={"foot-first","foot-second","right","inward-west","inward-north","crown","left-upper","left-lower"}
local children={
  {id="a",turn=0,offset={0,0}},
  {id="b",turn=0,offset={1,1}},
  {id="c",turn=1,offset={4,0}},
  {id="d",turn=3,offset={0,4}},
}
local function rotate(p,n)
  local x,y=p[1],p[2]
  if n==0 then return {x,y} end
  if n==1 then return {-y,x} end
  if n==2 then return {-x,-y} end
  if n==3 then return {y,-x} end
  error("aperiodic-invalid-rotation")
end
local function point_key(p) return p[1].."/"..p[2] end
local function edge_key(a,b)
  local u,v=point_key(a),point_key(b)
  if P.byte_less(v,u) then return v.."+"..u,true end
  return u.."+"..v,false
end
local function apply(t,p)
  local q=rotate(p,t.turn)
  return {t.offset[1]+t.scale*q[1],t.offset[2]+t.scale*q[2]}
end
local function rectangle(t,p)
  local a,b=apply(t,p),apply(t,{p[1]+1,p[2]+1})
  return {math.min(a[1],b[1]),math.min(a[2],b[2]),math.max(a[1],b[1]),math.max(a[2],b[2])}
end
local function child_transform(parent,spec)
  local s=parent.scale//2
  local p=rotate(spec.offset,parent.turn)
  return {offset={parent.offset[1]+p[1]*s,parent.offset[2]+p[2]*s},
    scale=s,turn=(parent.turn+spec.turn)%4,chirality=1}
end
local function intersects(a,b)
  return a[1]<b[3] and a[3]>b[1] and a[2]<b[4] and a[4]>b[2]
end
local function grid_coverage(t)
  local result={}
  for _,p in ipairs(occupied) do
    local box=rectangle(t,p)
    for x=box[1],box[3]-1 do for y=box[2],box[4]-1 do
      local key=point_key({x,y})
      assert(not result[key],"aperiodic-prototype-overlap")
      result[key]=true
    end end
  end
  return result
end
local function certify_rule()
  local root={offset={0,0},scale=2,turn=0,chirality=1}
  local expected=grid_coverage(root)
  for _,c in ipairs(children) do
    for key in pairs(grid_coverage(child_transform(root,c))) do
      assert(expected[key],"aperiodic-dissection-overlap-or-escape")
      expected[key]=nil
    end
  end
  assert(not next(expected),"aperiodic-dissection-gap")
end
certify_rule()

function M.prototype()
  return P.snapshot({id="chair/unit",integer_unit_squares=occupied,outline=outline,edge_labels=labels,
    allowed_isometries={quarter_turns={0,1,2,3},translation="integer lattice",reflection=false},
    matching={kind="geometry",class="unit-edge",opposite_directions=true,labels_force_substitution=false}})
end
function M.rule()
  return P.snapshot({id="chair/substitution-v1",expansion=2,children=children,
    certificate="exact 12-unit-square partition of the inflated prototype"})
end

local function sorted_keys(t)
  local out={}
  for key in pairs(t) do out[#out+1]=key end
  table.sort(out,P.byte_less)
  return out
end
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function valid_query(box,s)
  assert(#box==4,"aperiodic-query-box")
  for _,x in ipairs(box) do assert(finite(x),"aperiodic-query-coordinate") end
  assert(box[1]<box[3] and box[2]<box[4],"aperiodic-query-box")
  assert(box[1]>=0 and box[2]>=0 and box[3]<=2*s and box[4]<=2*s
    and (box[3]<=s or box[4]<=s),"aperiodic-outside-finite-horizon")
end
local function generate_root(depth,context)
  local leaves,nodes,physical_edges,coverage={},{},{},{}
  local root={offset={0,0},scale=2^depth,turn=0,chirality=1}
  root.scale=math.floor(root.scale)
  local function visit(t,address,level,parent)
    if context then context:consume("objects",1) end
    if level>0 then
      local node={transform=t,address=address,level=level,parent=parent,children={}}
      nodes[address]=node
      for _,c in ipairs(children) do
        local id=address..c.id
        node.children[#node.children+1]=id
        visit(child_transform(t,c),id,level-1,address)
      end
    else
      local leaf={address=address,parent=parent,transform=t,segments={},squares={}}
      leaves[#leaves+1]=leaf
      for _,p in ipairs(occupied) do
        local box=rectangle(t,p)
        local key=point_key({box[1],box[2]})
        assert(not coverage[key],"aperiodic-duplicate-or-overlap")
        coverage[key]=address
        leaf.squares[#leaf.squares+1]=box
      end
      for i,p in ipairs(outline) do
        local a,b=apply(t,p),apply(t,outline[i%#outline+1])
        local key,reversed=edge_key(a,b)
        if not physical_edges[key] then physical_edges[key]={from=reversed and b or a,to=reversed and a or b,uses={}} end
        local e=physical_edges[key]
        assert(#e.uses<2 and (#e.uses==0 or e.uses[1].reversed~=reversed),"aperiodic-global-seam-incidence")
        e.uses[#e.uses+1]={address=address,reversed=reversed}
        leaf.segments[i]={key=key,reversed=reversed,label=labels[i]}
      end
    end
  end
  visit(root,"r",depth)
  local expected=grid_coverage(root)
  local count=0
  for key in pairs(coverage) do assert(expected[key],"aperiodic-cell-outside-horizon");expected[key]=nil;count=count+1 end
  assert(not next(expected),"aperiodic-uncovered-root")
  return leaves,nodes,physical_edges,count
end

local function generate_patch(request,context)
  local depth,step,halo=request.depth,request.step_cm,request.halo
  assert(type(depth)=="number" and depth%1==0 and depth>=1 and depth<=4,"aperiodic-depth")
  assert(finite(step) and step>=.125 and step<=4,"aperiodic-leaf-step")
  assert(type(halo)=="number" and halo%1==0 and halo>=3 and halo<=8,"aperiodic-halo-below-leaf-diameter")
  local frame=request.frame
  local origin=frame.origin
  assert(frame.unit=="cm" and frame.dimension==2 and frame.handedness=="right"
    and finite(origin[1]) and finite(origin[2]) and math.abs(origin[1])<=1000 and math.abs(origin[2])<=1000,"aperiodic-frame")
  local side=math.floor(2^depth)
  local box=request.world_query
  local query={}
  for i,v in ipairs(box) do query[i]=(v-origin[(i-1)%2+1])/step end
  local expanded
  if not request.whole_root then
    valid_query(query,side)
    expanded={query[1]-halo,query[2]-halo,query[3]+halo,query[4]+halo}
  end
  local prefix="chair/"..H.value("chair/fixed-root",{frame=frame,depth=depth,step_cm=step,rule=M.rule().id})
  local function tile(address) return prefix.."/tile/"..address end
  local function parent(address) return prefix.."/supertile/"..address end
  local function vertex_id(point) return prefix.."/v/"..point_key(point) end
  local function world(p) return {origin[1]+step*p[1],origin[2]+step*p[2]} end
  local full,all_nodes,global_edges,coverage_count=generate_root(depth,context)
  local selected,selected_nodes={},{}
  local cells,edges,vertices,hierarchy=P.array(),P.array(),P.array(),P.array()
  local keep_edges,keep_vertices={},{}
  local function touch(leaf,b)
    if not b then return true end
    for _,s in ipairs(leaf.squares) do if intersects(s,b) then return true end end
    return false
  end
  local visible=0
  for _,leaf in ipairs(full) do
    if touch(leaf,query) then visible=visible+1 end
    if touch(leaf,expanded) then
      selected[leaf.address]=true
      local a=leaf.parent
      while a do selected_nodes[a]=true;a=all_nodes[a].parent end
      local boundary=P.array()
      for _,use in ipairs(leaf.segments) do
        keep_edges[use.key]=true
        boundary[#boundary+1]={edge=prefix.."/e/"..use.key,reversed=use.reversed,label=use.label}
      end
      local t=leaf.transform
      cells[#cells+1]={id=tile(leaf.address),address=leaf.address,prototype="chair/unit",chirality=1,
        parent=parent(leaf.parent),boundary=boundary,
        isometry={rotation_degrees=90*t.turn,reflection=false,translation=world(t.offset)},
        exact_transform=t,squares=leaf.squares}
    end
  end
  assert(#cells>0,"aperiodic-empty-query")
  for _,key in ipairs(sorted_keys(keep_edges)) do
    local e=global_edges[key]
    local neighbors,found=P.array(),{}
    for _,use in ipairs(e.uses) do
      neighbors[#neighbors+1]=tile(use.address)
      if selected[use.address] then found[#found+1]=tile(use.address) end
    end
    table.sort(neighbors,P.byte_less);table.sort(found,P.byte_less)
    local a,b=vertex_id(e.from),vertex_id(e.to)
    keep_vertices[a],keep_vertices[b]=e.from,e.to
    edges[#edges+1]={id=prefix.."/e/"..key,from=a,to=b,owner=found[1],
      role=#found==2 and "interior" or "patch_boundary",
      global_owner=neighbors[1],global_cells=neighbors,matching_class="unit-edge",
      boundary_reason=#found==2 and "none" or (#neighbors==1 and "root_boundary" or "query_cut")}
  end
  for _,id in ipairs(sorted_keys(keep_vertices)) do
    local v=keep_vertices[id]
    vertices[#vertices+1]={id=id,point=world(v),lattice=v}
  end
  for _,address in ipairs(sorted_keys(selected_nodes)) do
    local n=all_nodes[address]
    local members,complete=P.array(),P.array()
    for _,id in ipairs(n.children) do
      local ref=n.level==1 and tile(id) or parent(id)
      complete[#complete+1]=ref
      if selected[id] or selected_nodes[id] then members[#members+1]=ref end
    end
    hierarchy[#hierarchy+1]={id=parent(address),address=address,level=n.level,children=members,substitution_children=complete,
      parent=n.parent and parent(n.parent) or nil,prototype="chair/unit",exact_transform=n.transform}
  end
  if context then
    context:consume("objects",#cells+#vertices+#edges+#hierarchy)
    context:consume("operations",#full*12+#edges)
  end
  local certificate={source="L-triomino substitution",rule=M.rule().id,finite=true,globally_queryable=false,
    depth=depth,root=parent("r"),step_cm=step,world_origin=P.plain(origin),lattice_horizon={{0,0,2*side,side},{0,side,side,2*side}},
    query=query,whole_root=request.whole_root,halo_lattice_units=halo,root_leaf_count=#full,
    root_unit_square_count=coverage_count,selected_leaf_count=#cells,query_leaf_count=visible,
    hypotheses={"right handed metric frame","fixed root","unit edge coincidence","orientation-preserving quarter turns"},
    checks={"exact inflated dissection","root occupancy coverage and no overlap","global seam incidence",
      "stable address and directed boundaries","ancestral closure","query contained in finite horizon"}}
  return {prefix=prefix,tiling={vertices=vertices,edges=edges,cells=cells,hierarchy=hierarchy},certificate=certificate}
end

local function engine()
  local r=M.route_registry()
  r.register("hierarchical_substitution",{construct=generate_patch,validate=function(p)
    return #p.tiling.cells==p.certificate.selected_leaf_count and p.certificate.root_unit_square_count==3*4^p.certificate.depth
  end})
  return r
end

function M.definition()
  return P.definition({id="tiling/finite-substitution",version="1",family="finite-aperiodic-construction",
    units="cm",capabilities={"tiling"},parameters={
      root_depth={type="integer",minimum=1,maximum=4,required=true},
      leaf_step={type="number",minimum=.125,maximum=4,required=true},
      halo={type="integer",minimum=3,maximum=8},
      whole_root={type="boolean"},
      route={type="string",enum={"hierarchical_substitution","projection_multigrid","bounded_constraint"}}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Finite chair substitution fixture, no globally queryable claim",
      "Immutable root and integer leaf addresses with complete directed boundaries",
      "Projection/multigrid and bounded constraint routes require a registered provider"}})
end

local function audit_instance(tiling,request)
  local vertices,coverage,ancestors={},{},{}
  local origin,step=request.frame.origin,request.step_cm
  for _,v in ipairs(tiling.vertices) do
    local a=v.lattice
    assert(a[1]%1==0 and a[2]%1==0 and
      v.point[1]==origin[1]+step*a[1] and v.point[2]==origin[2]+step*a[2],"aperiodic-seam-coordinate")
    vertices[v.id]=a
  end
  for _,e in ipairs(tiling.edges) do
    local a,b=vertices[e.from],vertices[e.to]
    assert(math.abs(a[1]-b[1])+math.abs(a[2]-b[2])==1,"aperiodic-nonunit-seam")
  end
  for _,n in ipairs(tiling.hierarchy) do
    assert(#n.substitution_children==4 and n.exact_transform.chirality==1,"aperiodic-parent-child-certificate")
    for _,id in ipairs(n.children) do ancestors[id]=n.id end
  end
  for _,cell in ipairs(tiling.cells) do
    local t=cell.exact_transform
    assert(cell.chirality==1 and t.chirality==1 and cell.isometry.reflection==false
      and t.turn%1==0 and t.turn>=0 and t.turn<4 and cell.isometry.rotation_degrees==t.turn*90,
      "aperiodic-reflection-or-isometry")
    assert(cell.parent==ancestors[cell.id],"aperiodic-parent-child-certificate")
    assert(#cell.squares==3,"aperiodic-prototype-area")
    for _,s in ipairs(cell.squares) do
      local id=point_key({s[1],s[2]})
      assert(not coverage[id],"aperiodic-duplicate-or-overlap")
      coverage[id]=true
    end
  end
  for _,n in ipairs(tiling.hierarchy) do
    assert(n.parent==ancestors[n.id],"aperiodic-parent-child-certificate")
  end
end

local function validate(x)
  local e=x.extensions.substitution
  audit_instance(x.structures.tiling,e.request)
  local providers=engine()
  assert(P.serialize(e.prototype)==P.serialize(M.prototype()) and P.serialize(e.rule)==P.serialize(M.rule())
    and P.serialize(e.capabilities)==P.serialize(providers.capabilities()),"aperiodic-prototype-or-route-certificate")
  local reconstructed=providers.construct(e.route,P.plain(e.request))
  assert(P.serialize(reconstructed.tiling)==P.serialize(x.structures.tiling),"aperiodic-structure-reconstruction")
  assert(P.serialize(reconstructed.certificate)==P.serialize(e.certificate),"aperiodic-certificate-reconstruction")
  assert(P.serialize(x.frame)==P.serialize(e.request.frame),"aperiodic-request-frame")
  return {ok=true,checks=P.plain(e.certificate.checks),construction=P.plain(e.certificate)}
end
function M.validate(x)
  return validate(P.instance(P.plain(x),M.definition()))
end

local palette={{.26,.49,.65},{.86,.68,.32},{.28,.57,.55},{.67,.42,.38}}
local function lower(instance,view,style)
  for k in pairs(style) do assert(k=="stroke_width" or k=="stroke","aperiodic-style:"..k) end
  local width=style.stroke_width or .016
  assert(finite(width) and width>0 and width<.2,"aperiodic-stroke-width")
  local G=require("pattern_geometry")
  local t=instance.structures.tiling
  local vertices,projected,edges,operations={},{},{},{}
  local matrix=P.plain(view.transform)
  local crop=view.crop
  local request=instance.extensions.substitution.request
  if not request.whole_root then
    local inv=G.inverse(matrix,G.policy("cm",request.step_cm))
    local q=request.world_query
    for _,corner in ipairs{{crop[1],crop[2]},{crop[3],crop[2]},{crop[3],crop[4]},{crop[1],crop[4]}} do
      local p=G.transform(corner,inv)
      assert(p[1]>=q[1]-1e-10 and p[1]<=q[3]+1e-10 and p[2]>=q[2]-1e-10 and p[2]<=q[4]+1e-10,
        "aperiodic-view-outside-certified-query")
    end
  end
  for _,v in ipairs(t.vertices) do
    vertices[v.id]=v.point;projected[v.id]=G.transform(v.point,matrix)
  end
  for _,e in ipairs(t.edges) do edges[e.id]=e end
  local function visible(box,pad)
    return box[1]-pad<=crop[3] and box[3]+pad>=crop[1] and box[2]-pad<=crop[4] and box[4]+pad>=crop[2]
  end
  for _,cell in ipairs(t.cells) do
    local commands={}
    local box={math.huge,math.huge,-math.huge,-math.huge}
    for i,use in ipairs(cell.boundary) do
      local e=edges[use.edge]
      local id=use.reversed and e.to or e.from
      local a,b=vertices[id],projected[id]
      commands[i]={i==1 and "M" or "L",a[1],a[2]}
      box[1],box[2]=math.min(box[1],b[1]),math.min(box[2],b[2])
      box[3],box[4]=math.max(box[3],b[1]),math.max(box[4],b[2])
    end
    if visible(box,0) then
      commands[#commands+1]={"Z"}
      operations[#operations+1]={op="path",semantic_ref=cell.id,commands=commands,transform=matrix,
        paint={fill=palette[cell.exact_transform.turn+1]}}
    end
  end
  local pad=width*math.sqrt(matrix[1]^2+matrix[2]^2+matrix[3]^2+matrix[4]^2)
  for _,e in ipairs(t.edges) do
    local a,b=projected[e.from],projected[e.to]
    if visible({math.min(a[1],b[1]),math.min(a[2],b[2]),math.max(a[1],b[1]),math.max(a[2],b[2])},pad) then
      local p,q=vertices[e.from],vertices[e.to]
      operations[#operations+1]={op="path",semantic_ref=e.id,commands={{"M",p[1],p[2]},{"L",q[1],q[2]}},
        transform=matrix,paint={stroke=style.stroke or {.08,.13,.23},stroke_width=width}}
    end
  end
  return {id=instance.id.."/scene",instance_ref=instance.id,view_ref=view.id,unit="cm",validity=view.validity,
    clip={bounds=P.plain(view.crop),protected_regions=P.plain(view.protected_regions)},operations=operations,resources=P.array()}
end

function M.register(registry)
  local d=M.definition()
  local providers=engine()
  registry:register(d,{generate=function(s,context)
    local a=s.parameters
    local route=a.route or "hierarchical_substitution"
    local request={depth=a.root_depth,step_cm=a.leaf_step,halo=a.halo or 3,frame=P.plain(context.frame),
      world_query=P.plain(s.document.bounds),whole_root=a.whole_root or false}
    local p=providers.construct(route,request,context)
    return {id=p.prefix.."/query/"..H.value("chair/finite-query",request),definition_ref={id=d.id,version=d.version},
      frame=P.plain(context.frame),structures={tiling=p.tiling},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={substitution={route=route,request=request,certificate=p.certificate,
        capabilities=P.plain(providers.capabilities()),prototype=P.plain(M.prototype()),rule=P.plain(M.rule())}}}
  end,validate=validate,lower=lower})
  return d
end

return M
