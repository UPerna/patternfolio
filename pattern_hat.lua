local P,H,G=require("pattern"),require("pattern_hash"),require("pattern_geometry")
local Rules=require("pattern_hat_rules")
local M={VERSION="hat-four-metatile-polykite-v1"}
local sqrt3=math.sqrt(3)
local function key(p) return table.concat(p,"/") end
local function sorted_keys(t)
  local keys={}
  for k in pairs(t) do keys[#keys+1]=k end
  table.sort(keys,P.byte_less)
  return keys
end
local function cross(a,b) return a[1]*b[2]-a[2]*b[1] end
local function area2(points)
  local total=0
  for i,a in ipairs(points) do total=total+cross(a,points[i%#points+1]) end
  return total
end
local function winding(points)
  if area2(points)>0 then return points end
  local out={points[1]}
  for i=#points,2,-1 do out[#out+1]=points[i] end
  return out
end
local function side(p,q)
  local a,b=key(p),key(q)
  if P.byte_less(b,a) then return b.."+"..a,true end
  return a.."+"..b,false
end
local function polygon_signature(points)
  local keys={}
  for i,p in ipairs(points) do keys[i]=key(p) end
  table.sort(keys,P.byte_less)
  return table.concat(keys,"+")
end
local kite_shapes={}
do
  local corners={{0,0},{1,1},{0,2},{-1,2}}
  for _=1,6 do
    kite_shapes[polygon_signature(corners)]=true
    for i,p in ipairs(corners) do corners[i]={-p[2],p[1]+p[2]} end
  end
end
local function simplified_cycle(points)
  local turns={}
  for i,p in ipairs(points) do
    local a,b=points[(i-2)%#points+1],points[i%#points+1]
    if cross({p[1]-a[1],p[2]-a[2]},{b[1]-p[1],b[2]-p[2]})~=0 then
      turns[#turns+1]=key(p)
    end
  end
  local start=1
  for i=2,#turns do if P.byte_less(turns[i],turns[start]) then start=i end end
  local out={}
  for i=1,#turns do out[i]=turns[(i+start-2)%#turns+1] end
  return table.concat(out,"+")
end
local function certify(cluster)
  local occupied,seams={},{}
  local coset
  for n,item in ipairs(cluster.leaves) do
    assert(#item.points==13 and #item.kites==8,"hat-polykite-prototype")
    assert(area2(item.points)==(item.transform.reflected and -32 or 32),"hat-prototype-orientation")
    local local_sides={}
    for _,raw in ipairs(item.kites) do
      local center=raw[1]
      local u,v=center[1],center[2]
      local residue=key({(2*u+v)%6,(v-u)%6})
      coset=coset or residue
      assert(coset==residue,"hat-incompatible-kite-center-coset")
      local relative={}
      for i,p in ipairs(raw) do relative[i]={p[1]-u,p[2]-v} end
      assert(kite_shapes[polygon_signature(relative)],"hat-off-grid-kite")
      local signature=polygon_signature(raw)
      assert(not occupied[signature],"hat-kite-overlap")
      occupied[signature]=true
      local points=winding(raw)
      assert(area2(points)==4,"hat-kite-area")
      for i,p in ipairs(points) do
        local q=points[i%4+1]
        local id,reverse=side(p,q)
        local prior=local_sides[id]
        assert(not prior or (not prior.paired and prior.reverse~=reverse),"hat-interior-kite-incidence")
        if prior then prior.paired=true else local_sides[id]={from=p,to=q,reverse=reverse} end
      end
    end
    local outgoing={}
    local boundary_size=0
    for _,edge in pairs(local_sides) do
      if not edge.paired then
        local id=key(edge.from)
        assert(not outgoing[id],"hat-branching-leaf-boundary")
        outgoing[id]=edge
        boundary_size=boundary_size+1
      end
    end
    item.boundary={}
    local start=key(item.points[1])
    local at=start
    for i=1,boundary_size do
      local e=assert(outgoing[at],"hat-open-leaf-boundary")
      outgoing[at]=nil
      item.boundary[i]=e.from
      at=key(e.to)
      local id,reverse=side(e.from,e.to)
      local seam=seams[id]
      if not seam then
        seam={from=reverse and e.to or e.from,to=reverse and e.from or e.to,uses={}}
        seams[id]=seam
      end
      assert(#seam.uses<2 and (#seam.uses==0 or seam.uses[1].reverse~=reverse),"hat-root-seam-incidence")
      seam.uses[#seam.uses+1]={leaf=n,reverse=reverse}
    end
    assert(at==start and simplified_cycle(item.boundary)==simplified_cycle(winding(item.points)),"hat-kite-outline")
  end
  local neighbors,balance={},{}
  local root_area,shared,border=0,0,0
  for _,edge in pairs(seams) do
    local a,b=edge.uses[1],edge.uses[2]
    if b then
      neighbors[a.leaf]=neighbors[a.leaf] or {}
      neighbors[b.leaf]=neighbors[b.leaf] or {}
      neighbors[a.leaf][#neighbors[a.leaf]+1]=b.leaf
      neighbors[b.leaf][#neighbors[b.leaf]+1]=a.leaf
      shared=shared+1
    else
      local p,q=edge.from,edge.to
      if a.reverse then p,q=q,p end
      root_area=root_area+cross(p,q)
      balance[key(p)]=(balance[key(p)] or 0)+1
      balance[key(q)]=(balance[key(q)] or 0)-1
      border=border+1
    end
  end
  for _,n in pairs(balance) do assert(n==0,"hat-open-root-boundary") end
  local queue,seen={1},{[1]=true}
  local i=1
  while queue[i] do
    for _,n in ipairs(neighbors[queue[i]] or {}) do
      if not seen[n] then seen[n]=true;queue[#queue+1]=n end
    end
    i=i+1
  end
  local count=#cluster.leaves
  assert(#queue==count and root_area==32*count,"hat-root-area-or-connectivity")
  return seams,{tiles=count,kites=8*count,reflected=cluster.reflection_count,
    root_boundary_edges=border,shared_edges=shared,area2=root_area,center_coset=coset}
end
local function extent(points)
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,p in ipairs(points) do
    x0,y0,x1,y1=math.min(x0,p[1]),math.min(y0,p[2]),math.max(x1,p[1]),math.max(y1,p[2])
  end
  return {x0,y0,x1,y1}
end
local function hits(a,b,e)
  return a[1]<=b[3]+e and a[3]+e>=b[1] and a[2]<=b[4]+e and a[4]+e>=b[2]
end
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function construct(request,context)
  local frame,step,query=request.frame,request.step_cm,request.world_query
  assert(frame.unit=="cm" and frame.dimension==2 and frame.handedness=="right","hat-frame")
  assert(finite(step) and step>=.1 and step<=1,"hat-step")
  assert(#query==4 and query[1]<query[3] and query[2]<query[4],"hat-query")
  local cluster=Rules.cluster(request.root,request.depth)
  if context then context:consume("operations",#cluster.leaves*140) end
  local seams,proof=certify(cluster)
  local prefix="hat/"..H.value("hat/root",{root=request.root,depth=request.depth,step=step,frame=frame,method=M.VERSION})
  local function cell_id(item) return prefix.."/leaf/"..table.concat(item.address,".") end
  local function vertex_id(p) return prefix.."/v/"..key(p) end
  local function world(p)
    return {frame.origin[1]+step*(p[1]+p[2]/2),frame.origin[2]+step*(sqrt3/2*p[2])}
  end
  local visible,points={},{}
  local cells,edges,vertices=P.array(),P.array(),P.array()
  for n,item in ipairs(cluster.leaves) do
    local world_outline={}
    for i,p in ipairs(item.points) do world_outline[i]=world(p) end
    if request.whole_root or hits(extent(world_outline),query,.04) then
      visible[n]=true
      local boundary={}
      for i,p in ipairs(item.boundary) do
        local q=item.boundary[i%#item.boundary+1]
        local id,reversed=side(p,q)
        boundary[i]={edge=prefix.."/e/"..id,reversed=reversed}
        points[key(p)]=p
      end
      local t=item.transform
      cells[#cells+1]={id=cell_id(item),prototype="hat-eight-kite",chirality=t.reflected and -1 or 1,
        boundary=boundary,address=item.address,parent_address=item.parent,label=item.label,
        lattice_transform=t,outline=item.points,kites=item.kites,
        isometry={rotation_degrees=60*t.turn,reflection=t.reflected,translation=world(t.offset)}}
    end
  end
  for _,id in ipairs(sorted_keys(seams)) do
    local e=seams[id]
    local global,selected={},{}
    for _,use in ipairs(e.uses) do
      local cid=cell_id(cluster.leaves[use.leaf])
      global[#global+1]=cid
      if visible[use.leaf] then selected[#selected+1]=cid end
    end
    if #selected>0 then
      table.sort(global,P.byte_less);table.sort(selected,P.byte_less)
      local interior=#selected==2
      edges[#edges+1]={id=prefix.."/e/"..id,from=vertex_id(e.from),to=vertex_id(e.to),
        role=interior and "interior" or "patch_boundary",owner=selected[1],global_cells=global,global_owner=global[1],
        boundary_reason=interior and "none" or (#global==1 and "root_boundary" or "query_cut")}
    end
  end
  for _,id in ipairs(sorted_keys(points)) do
    local p=points[id]
    vertices[#vertices+1]={id=vertex_id(p),point=world(p),lattice=p}
  end
  assert(#cells>0,"hat-empty-query")
  if context then context:consume("objects",#cells+#edges+#vertices+#cluster.nodes) end
  proof.method=M.VERSION
  proof.reference_hash=H.sha256(cluster.reference_bytes)
  proof.selected_tiles=#cells
  proof.checks={"four source metatile recurrences and canonical cluster addresses",
    "eight distinct elementary kites per Hat with common global center coset",
    "both prototype orientations retained and matched to determinant",
    "closed exact leaf boundaries and opposite shared edge incidence",
    "connected root and exact lattice area correspondence"}
  return {prefix=prefix,tiling={cells=cells,edges=edges,vertices=vertices},hierarchy=cluster.nodes,certificate=proof}
end
function M.definition()
  return P.definition({id="tiling/hat",version="1",family="hat-four-metatile",units="cm",capabilities={"tiling"},
    parameters={root={type="string",enum={"H","T","P","F"}},depth={type="integer",minimum=1,maximum=3,required=true},
      kite_edge={type="number",minimum=.1,maximum=1,required=true},whole_root={type="boolean"}},
    transforms={metric_constrained=true,reflection=true,uniform_scale=true},
    assumptions={"The Hat's eight-kite geometry and both leaf orientations",
      "Finite H/T/P/F hierarchy with exact metatile guides and a separate leaf-union proof"}})
end
local function routes()
  local r=require("pattern_aperiodic").route_registry()
  r.register("hierarchical_substitution",{construct=construct,validate=function(p)
    return p.certificate.kites==8*p.certificate.tiles and p.certificate.area2==32*p.certificate.tiles
  end})
  return r
end
local function validate(x)
  local e=x.extensions.hat
  local r=routes()
  assert(e.route=="hierarchical_substitution" and P.serialize(e.request.frame)==P.serialize(x.frame),"hat-route-frame")
  assert(P.serialize(e.capabilities)==P.serialize(r.capabilities()),"hat-route-capabilities")
  local actual=r.construct(e.route,P.plain(e.request))
  assert(P.serialize(actual.tiling)==P.serialize(x.structures.tiling),"hat-geometry-reconstruction")
  assert(P.serialize(actual.hierarchy)==P.serialize(e.hierarchy),"hat-hierarchy-reconstruction")
  assert(P.serialize(actual.certificate)==P.serialize(e.certificate),"hat-certificate-reconstruction")
  return {ok=true,checks=P.plain(e.certificate.checks),construction=P.plain(e.certificate)}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end
local palette={H={.25,.48,.63},H1={.71,.32,.25},T={.69,.55,.33},P={.41,.60,.52},F={.61,.56,.68}}
local function lower(x,v,style)
  for k in pairs(style) do assert(k=="display","hat-style:"..k) end
  local display=style.display or "lineage"
  assert(display=="lineage" or display=="kites","hat-display")
  local request=x.extensions.hat.request
  local crop,transform=v.crop,P.plain(v.transform)
  local inverse=G.inverse(transform,G.policy("cm",request.step_cm))
  local query=request.world_query
  for _,p in ipairs{{crop[1],crop[2]},{crop[3],crop[2]},{crop[3],crop[4]},{crop[1],crop[4]}} do
    local q=G.transform(p,inverse)
    assert(q[1]>=query[1]-1e-10 and q[1]<=query[3]+1e-10 and q[2]>=query[2]-1e-10 and q[2]<=query[4]+1e-10,
      "hat-view-outside-query")
  end
  local function point(p)
    return {x.frame.origin[1]+request.step_cm*(p[1]+p[2]/2),
      x.frame.origin[2]+request.step_cm*(sqrt3/2*p[2])}
  end
  local ops=P.array()
  local scale=math.sqrt(transform[1]^2+transform[2]^2+transform[3]^2+transform[4]^2)
  local function path(ref,lattice,paint)
    local cmds,view_points={},{}
    for i,p in ipairs(lattice) do
      local q=point(p)
      view_points[i]=G.transform(q,transform)
      cmds[i]={i==1 and "M" or "L",q[1],q[2]}
    end
    if hits(extent(view_points),crop,(paint.stroke_width or 0)*scale) then
      cmds[#cmds+1]={"Z"}
      ops[#ops+1]={op="path",semantic_ref=ref,commands=cmds,transform=transform,paint=paint}
    end
  end
  for _,c in ipairs(x.structures.tiling.cells) do
    path(c.id,c.outline,{fill=palette[c.label]})
    if display=="kites" then
      for _,kite in ipairs(c.kites) do
        path(c.id,kite,{stroke={.92,.93,.90},stroke_width=.008,opacity=.72})
      end
    end
  end
  local points={}
  for _,p in ipairs(x.structures.tiling.vertices) do points[p.id]=p.point end
  for _,e in ipairs(x.structures.tiling.edges) do
    local a,b=points[e.from],points[e.to]
    if hits(extent{G.transform(a,transform),G.transform(b,transform)},crop,.012*scale) then
      ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",a[1],a[2]},{"L",b[1],b[2]}},
        transform=transform,paint={stroke={.13,.19,.23},stroke_width=.012}}
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end
function M.register(registry)
  local d,r=M.definition(),routes()
  registry:register(d,{generate=function(s,c)
    local a=s.parameters
    local request={root=a.root or "H",depth=a.depth,step_cm=a.kite_edge,whole_root=a.whole_root==true,
      frame=P.plain(c.frame),world_query=P.plain(s.document.bounds)}
    local p=r.construct("hierarchical_substitution",request,c)
    return {id=p.prefix.."/query/"..H.value("hat/query",request),definition_ref={id=d.id,version=d.version},
      frame=P.plain(c.frame),structures={tiling=p.tiling},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={hat={route="hierarchical_substitution",request=request,certificate=p.certificate,
        hierarchy=p.hierarchy,capabilities=P.plain(r.capabilities())}}}
  end,validate=validate,lower=lower})
  return d
end
return M
