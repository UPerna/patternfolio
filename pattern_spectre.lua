-- Smith, Myers, Kaplan and Goodman-Strauss (2024), Figures 2.1 and 5.1.
-- Exact 30-degree lattice coordinates: (a+b*sqrt(3), c+d*sqrt(3))/2.
local P,H=require("pattern"),require("pattern_hash")
local M={VERSION="spectre-s-curve-hierarchy-v1"}
local root3=math.sqrt(3)
local names={G="Gamma",D="Delta",T="Theta",L="Lambda",X="Xi",P="Pi",S="Sigma",F="Phi",Y="Psi"}
local inverse={}
for id,name in pairs(names) do inverse[name]=id end
local slots={
  G="PD-TSXFG",D="XDXFSPFG",T="YDPFSPFG",L="YDXFSPFG",X="YDPFSYFG",
  P="YDXFSYFG",S="XDXFSPLG",F="YDYFSPFG",Y="YDYFSYFG",
}
local function point(a,b,c,d) return {a,b,c,d} end
local zero=point(0,0,0,0)
local function add(p,q) return point(p[1]+q[1],p[2]+q[2],p[3]+q[3],p[4]+q[4]) end
local function sub(p,q) return point(p[1]-q[1],p[2]-q[2],p[3]-q[3],p[4]-q[4]) end
local function times(p,s) return point(p[1]*s,p[2]*s,p[3]*s,p[4]*s) end
local function ninety(p) return point(-p[3],-p[4],p[1],p[2]) end
local function mirror(p) return point(-p[1],-p[2],p[3],p[4]) end
local function rotate(p,turn)
  for _=1,turn%12 do
    local a,b,c,d=table.unpack(p)
    assert((3*b-c)%2==0 and (a-d)%2==0 and (a+3*d)%2==0 and (b+c)%2==0,"spectre-lattice-parity")
    p=point((3*b-c)//2,(a-d)//2,(a+3*d)//2,(b+c)//2)
  end
  return p
end
local function map(t,p)
  if t.reflected then p=mirror(p) end
  return add(t.offset,rotate(p,t.turn))
end
local function compose(a,b)
  return {turn=(a.turn+(a.reflected and -b.turn or b.turn))%12,
    reflected=a.reflected~=b.reflected,offset=map(a,b.offset)}
end
local function same(p,q)
  return p[1]==q[1] and p[2]==q[2] and p[3]==q[3] and p[4]==q[4]
end
local function xy(p,denominator)
  local d=denominator or 2
  return {(p[1]+p[2]*root3)/d,(p[3]+p[4]*root3)/d}
end
local function scalar_mul(a,b,c,d)
  return a*c+3*b*d,a*d+b*c
end
local function cross(p,q)
  local a,b=scalar_mul(p[1],p[2],q[3],q[4])
  local c,d=scalar_mul(p[3],p[4],q[1],q[2])
  return a-c,b-d
end
local function sign(a,b)
  if a==0 then return b<0 and -1 or b>0 and 1 or 0 end
  if b==0 or (a<0)==(b<0) then return a<0 and -1 or 1 end
  assert(math.abs(a)<=2^29 and math.abs(b)<=2^29,"spectre-exact-sign-budget")
  local n=a*a-3*b*b
  return ((a<0)==(n>0)) and -1 or 1
end
local function exact_area(poly)
  local a,b=0,0
  local origin=poly[1]
  for i=2,#poly-1 do
    local x,y=cross(sub(poly[i],origin),sub(poly[i+1],origin))
    a,b=a+x,b+y
  end
  return {rational=a,radical=b,denominator=8,radicand=3}
end
local turns={0,10,1,3,0,2,5,7,4,6,6,8,11,9}
local outline={}
local p=zero
for _,t in ipairs(turns) do
  outline[#outline+1]=p
  p=add(p,rotate(point(2,0,0,0),t))
end
assert(same(p,zero),"spectre-prototype-closure")
local unit_area=exact_area(outline)
assert(sign(unit_area.rational,unit_area.radical)>0,"spectre-prototype-orientation")
local base_quad={outline[4],outline[6],outline[8],outline[12]}
local joins={{2,4,2},{0,3,1},{2,4,2},{2,4,2},{0,3,1},{2,4,2},{-4,4,4}}
local next_anchors={{7,3},{6,2},{4,3},{1,2}}

local function levels(depth)
  local quad=base_quad
  local result={}
  for i=1,depth do
    local placed={{turn=0,reflected=false,offset=zero}}
    for j,join in ipairs(joins) do
      local previous=placed[j]
      local turn=(previous.turn+join[1])%12
      local vertex=map(previous,quad[join[2]])
      placed[j+1]={turn=turn,reflected=false,offset=sub(vertex,rotate(quad[join[3]],turn))}
      assert(same(map(placed[j+1],quad[join[3]]),vertex),"spectre-slot-anchor")
    end
    local reflect={turn=0,reflected=true,offset=zero}
    for j,t in ipairs(placed) do placed[j]=compose(reflect,t) end
    local next_quad={}
    for j,mark in ipairs(next_anchors) do next_quad[j]=map(placed[mark[1]],quad[mark[2]]) end
    result[i]={children=placed,quad=next_quad}
    quad=next_quad
  end
  return result
end
local function round(x) return math.floor(x*1e6+.5) end
local function full(depth,root_type,context)
  local root=assert(inverse[root_type],"spectre-root-type")
  assert(type(depth)=="number" and depth%1==0 and depth>=1 and depth<=3,"spectre-root-depth")
  local rules=levels(depth)
  local leaves,nodes,reference={},{},{}
  local function emit(t,name,address,parent)
    assert(not t.reflected,"spectre-illicit-reflected-leaf")
    if context then context:consume("operations",#outline) end
    local vertices,row={},{}
    for i,v in ipairs(outline) do
      vertices[i]=map(t,v)
      local a=xy(vertices[i])
      row[i]={round(a[1]),round(a[2])}
    end
    reference[#reference+1]={name,row}
    leaves[#leaves+1]={address=address,parent=parent,transform=t,vertices=vertices,label=name,ordinal=#leaves+1}
  end
  local function walk(t,typ,depth,address,parent)
    if context then context:consume("objects",1) end
    if depth==0 and typ~="G" then emit(t,names[typ],address,parent);return end
    local n={address=address,parent=parent,type=names[typ],level=depth,transform=t,children={}}
    nodes[address]=n
    if depth==0 then
      n.children={{address=address.."a",kind="leaf"},{address=address.."b",kind="leaf"}}
      emit(t,"Gamma1",address.."a",address)
      emit(compose(t,{turn=1,reflected=false,offset=outline[9]}),"Gamma2",address.."b",address)
    else
      for slot=1,8 do
        local child=slots[typ]:sub(slot,slot)
        if child~="-" then
          local id=address..slot
          n.children[#n.children+1]={address=id,kind=(depth==1 and child~="G") and "leaf" or "node"}
          walk(compose(t,rules[depth].children[slot]),child,depth-1,id,address)
        end
      end
    end
  end
  walk({turn=0,reflected=depth%2==1,offset=zero},root,depth,"r")
  return leaves,nodes,H.sha256(P.serialize(reference)),rules
end
function M.reference(depth,root)
  local leaves,_,digest=full(depth,root)
  return {count=#leaves,digest=digest,area=unit_area}
end
local function key(p) return table.concat(p,"/") end
local function sorted_keys(map)
  local out={}
  for k in pairs(map) do out[#out+1]=k end
  table.sort(out,P.byte_less)
  return out
end
local function edge_key(a,b)
  if P.byte_less(b,a) then return b.."+"..a,true end
  return a.."+"..b,false
end
local function controls(a,b)
  local d=sub(b,a)
  local n=ninety(d)
  return add(add(times(a,96),times(d,32)),times(n,6)),
    sub(add(times(a,96),times(d,64)),times(n,6))
end
local function bounds(poly,denominator)
  local b={math.huge,math.huge,-math.huge,-math.huge}
  for _,v in ipairs(poly) do
    local q=xy(v,denominator)
    b[1],b[2]=math.min(b[1],q[1]),math.min(b[2],q[2])
    b[3],b[4]=math.max(b[3],q[1]),math.max(b[4],q[2])
  end
  return b
end
local function grow(b,m)
  return {b[1]-m,b[2]-m,b[3]+m,b[4]+m}
end
local function meet(a,b,pad)
  return a[1]-pad<=b[3] and a[3]+pad>=b[1] and a[2]-pad<=b[4] and a[4]+pad>=b[2]
end
local function less(a,b) return sign(a[1]-b[1],a[2]-b[2])<0 end
local function projection(hull,origin,axis)
  local lo,hi
  for _,p in ipairs(hull) do
    local a,b=cross(axis,sub(p,origin))
    local value={a,b}
    if not lo or less(value,lo) then lo=value end
    if not hi or less(hi,value) then hi=value end
  end
  return lo,hi
end
local function separated(p,q,touch)
  for _,hull in ipairs{p,q} do
    for i,o in ipairs(hull) do
      local axis=sub(hull[i%#hull+1],o)
      local alo,ahi=projection(p,o,axis)
      local blo,bhi=projection(q,o,axis)
      local left=sign(ahi[1]-blo[1],ahi[2]-blo[2])
      local right=sign(bhi[1]-alo[1],bhi[2]-alo[2])
      if left<0 or right<0 or touch and (left==0 or right==0) then return true end
    end
  end
  return false
end
local function validate_hulls(edges,context)
  local sequence={}
  for _,e in pairs(edges) do
    local a,b=times(e.a,96),times(e.b,96)
    e.hull={a,e.c2,b,e.c1}
    e.box=bounds(e.hull,192)
    sequence[#sequence+1]=e
  end
  table.sort(sequence,function(a,b)
    if a.box[1]==b.box[1] then return P.byte_less(a.id,b.id) end
    return a.box[1]<b.box[1]
  end)
  local tests=0
  for i,a in ipairs(sequence) do
    for j=i+1,#sequence do
      local b=sequence[j]
      if b.box[1]>a.box[3]+1e-10 then break end
      if meet(a.box,b.box,1e-10) then
        local shared=same(a.a,b.a) or same(a.a,b.b) or same(a.b,b.a) or same(a.b,b.b)
        assert(separated(a.hull,b.hull,shared),"spectre-curve-hull-intersection:"..a.id.."+"..b.id)
        tests=tests+1
      end
    end
  end
  if context then context:consume("operations",tests) end
  return tests
end
local function global_complex(leaves,context)
  local points,edges,duplicates={},{},{}
  for _,leaf in ipairs(leaves) do
    local ids={}
    for i,p in ipairs(leaf.vertices) do ids[i]=key(p);points[ids[i]]=p end
    local signature={table.unpack(ids)}
    table.sort(signature,P.byte_less)
    signature=table.concat(signature,"+")
    assert(not duplicates[signature],"spectre-duplicate-tile")
    duplicates[signature]=true
    leaf.uses={}
    leaf.box=bounds(leaf.vertices)
    for i,a in ipairs(ids) do
      local b=ids[i%#ids+1]
      local id,reversed=edge_key(a,b)
      local e=edges[id]
      if not e then
        local p,q=points[reversed and b or a],points[reversed and a or b]
        local c1,c2=controls(p,q)
        e={id=id,from=reversed and b or a,to=reversed and a or b,a=p,b=q,c1=c1,c2=c2,uses={}}
        edges[id]=e
      end
      assert(#e.uses<2 and (#e.uses==0 or e.uses[1].reversed~=reversed),"spectre-edge-pairing")
      e.uses[#e.uses+1]={address=leaf.address,reversed=reversed}
      leaf.uses[i]={id=id,reversed=reversed}
    end
  end
  local adjacency,balance={},{}
  local outside,inside=0,0
  local area_a,area_b=0,0
  for _,leaf in ipairs(leaves) do adjacency[leaf.address]={} end
  for _,e in pairs(edges) do
    if #e.uses==1 then
      outside=outside+1
      local rev=e.uses[1].reversed
      local p,q=rev and e.b or e.a,rev and e.a or e.b
      local a,b=cross(p,q)
      area_a,area_b=area_a+a,area_b+b
      local s,t=key(p),key(q)
      balance[s]=(balance[s] or 0)+1
      balance[t]=(balance[t] or 0)-1
    else
      inside=inside+1
      local a,b=e.uses[1].address,e.uses[2].address
      adjacency[a][#adjacency[a]+1]=b
      adjacency[b][#adjacency[b]+1]=a
    end
  end
  for _,value in pairs(balance) do assert(value==0,"spectre-open-root-boundary") end
  assert(area_a==#leaves*unit_area.rational and area_b==#leaves*unit_area.radical,"spectre-root-area-correspondence")
  local first=leaves[1].address
  local seen,queue={[first]=true},{first}
  local i=1
  while i<=#queue do
    for _,id in ipairs(adjacency[queue[i]]) do
      if not seen[id] then seen[id]=true;queue[#queue+1]=id end
    end
    i=i+1
  end
  assert(#queue==#leaves,"spectre-disconnected-root")
  local pairs=validate_hulls(edges,context)
  return points,edges,{root_boundary_edges=outside,root_shared_edges=inside,hull_pairs=pairs,
    root_area={rational=area_a,radical=area_b,denominator=8,radicand=3}}
end
function M.check_root(depth,kind)
  local leaves,_,digest=full(depth,kind)
  local _,_,proof=global_complex(leaves)
  return {leaves=#leaves,digest=digest,proof=proof}
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function patch(request,context)
  local depth,root=request.depth,request.root
  local leaves,nodes,reference,rules=full(depth,root,context)
  local points,edges,proof=global_complex(leaves,context)
  local frame=request.frame
  local origin=frame.origin
  local step=request.step_cm
  assert(finite(step) and step>=.1 and step<=2,"spectre-edge-length")
  assert(frame.unit=="cm" and frame.dimension==2 and frame.handedness=="right","spectre-frame")
  assert(request.boundary=="spectre-s" or request.boundary=="tile-1-1","spectre-boundary-profile")
  local whole=request.whole_root
  local query={}
  for i,q in ipairs(request.world_query) do
    query[i]=(q-origin[(i-1)%2+1])/step
    assert(finite(query[i]) and math.abs(query[i])<=4096,"spectre-query-coordinate")
  end
  local halo=request.halo
  assert(finite(halo) and halo>=4 and halo<=8,"spectre-query-halo")
  local expanded=grow(query,halo)
  local prefix="spectre/"..H.value("spectre/finite-root",{depth=depth,root=root,frame=frame,step_cm=step,method=M.VERSION})
  local function tile_id(a) return prefix.."/tile/"..a end
  local function node_id(a) return prefix.."/cluster/"..a end
  local function vertex_id(a) return prefix.."/v/"..a end
  local function edge_id(a) return prefix.."/e/"..a end
  local function world(exact,denominator)
    local v=xy(exact,denominator)
    return {origin[1]+step*v[1],origin[2]+step*v[2]}
  end
  local selected,ancestors,kept_edges,kept_vertices={},{},{},{}
  local cells,boundaries,vertices,hierarchy=P.array(),P.array(),P.array(),P.array()
  for _,leaf in ipairs(leaves) do
    if whole or meet(leaf.box,expanded,.063) then
      selected[leaf.address]=true
      local a=leaf.parent
      while a do ancestors[a]=true;a=nodes[a].parent end
      local b=P.array()
      for i,use in ipairs(leaf.uses) do
        kept_edges[use.id]=true
        b[i]={edge=edge_id(use.id),reversed=use.reversed,prototype_edge=i}
      end
      local t=leaf.transform
      cells[#cells+1]={id=tile_id(leaf.address),prototype="tile-1-1-equilateral",chirality=1,address=leaf.address,
        lineage_label=leaf.label,reference_ordinal=leaf.ordinal,parent=node_id(leaf.parent),boundary=b,
        exact_transform=t,isometry={rotation_degrees=30*t.turn,reflection=false,translation=world(t.offset)}}
    end
  end
  assert(#cells>0 and #cells<=200,"spectre-selected-cell-budget")
  local cuts=0
  for _,key in ipairs(sorted_keys(kept_edges)) do
    local e=edges[key]
    local global,local_={},{}
    for _,use in ipairs(e.uses) do
      local id=tile_id(use.address)
      global[#global+1]=id
      if selected[use.address] then local_[#local_+1]=id end
    end
    table.sort(global,P.byte_less);table.sort(local_,P.byte_less)
    local internal=#local_==2
    local reason=internal and "none" or #global==1 and "root_boundary" or "query_cut"
    if reason=="query_cut" then cuts=cuts+1 end
    kept_vertices[e.from],kept_vertices[e.to]=true,true
    local cubic
    if request.boundary=="spectre-s" then
      cubic={kind="centrally_symmetric_cubic",denominator=192,control1=e.c1,control2=e.c2}
    end
    boundaries[#boundaries+1]={id=edge_id(key),from=vertex_id(e.from),to=vertex_id(e.to),owner=local_[1],
      role=internal and "interior" or "patch_boundary",boundary_reason=reason,global_owner=global[1],global_cells=global,curve=cubic}
  end
  for _,k in ipairs(sorted_keys(kept_vertices)) do
    vertices[#vertices+1]={id=vertex_id(k),point=world(points[k]),lattice=points[k]}
  end
  for _,a in ipairs(sorted_keys(ancestors)) do
    local node=nodes[a]
    local members,complete=P.array(),P.array()
    for _,child in ipairs(node.children) do
      local id=child.kind=="leaf" and tile_id(child.address) or node_id(child.address)
      complete[#complete+1]=id
      if selected[child.address] or ancestors[child.address] then members[#members+1]=id end
    end
    hierarchy[#hierarchy+1]={id=node_id(a),address=a,type=node.type,level=node.level,
      parent=node.parent and node_id(node.parent) or nil,children=members,source_children=complete,
      exact_transform=node.transform}
  end
  if context then context:consume("objects",#cells+#boundaries+#vertices+#hierarchy) end
  local certificate={method=M.VERSION,source="Smith, Myers, Kaplan and Goodman-Strauss 2024, Figures 2.1 and 5.1; Lemma 2.1",
    root_type=root,depth=depth,frame=P.plain(frame),normalized_odd_depth_reflection=depth%2==1,
    geometry_case=request.boundary=="spectre-s" and "strictly_chiral_s_curve_spectre" or "weakly_chiral_tile_1_1_diagnostic",
    strictly_chiral=request.boundary=="spectre-s",finite=true,root_leaf_count=#leaves,selected_leaf_count=#cells,
    exact_outline=P.plain(outline),unit_area=unit_area,root_complex=proof,reference_coordinate_digest=reference,
    root_quad=rules[depth].quad,halo_edge_units=halo,query_cuts=cuts,normalized_query=query,
    control_profile={tangent_offset={1,16},evaluation_tolerance_cm=1e-10,central_symmetry=true,exact_coefficient_denominator=192,
      world_realization="binary64 coordinates from exact quadratic coefficients"},
    hypotheses={"one chirality at leaf level","source cluster joins","whole unit edges","centrally symmetric edge replacement"},
    checks={"exact source slot anchors and transforms","homochiral leaves and duplicate rejection","paired unit edge incidence",
      "closed root boundary and exact area correspondence","exact cubic control hull separation","fixed root query and lineage"}}
  return {prefix=prefix,tiling={cells=cells,edges=boundaries,vertices=vertices,hierarchy=hierarchy},certificate=certificate}
end

function M.definition()
  return P.definition({id="tiling/spectre",version="1",family="spectre-marked-hierarchy",units="cm",capabilities={"tiling"},
    parameters={depth={type="integer",minimum=1,maximum=3,required=true},
      root={type="string",enum={"Gamma","Delta","Theta","Lambda","Xi","Pi","Sigma","Phi","Psi"}},
      edge_length={type="number",minimum=.1,maximum=2,required=true},
      boundary={type="string",enum={"spectre-s","tile-1-1"}},whole_root={type="boolean"},
      halo={type="number",minimum=4,maximum=8}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Published marked hierarchy on a bounded root; no mixed reflected leaves",
      "A centrally symmetric smooth S curve is the genuine Spectre case",
      "Straight Tile(1,1) is a separately identified diagnostic; the Hat is distinct"}})
end
local function provider()
  local routes=require("pattern_aperiodic").route_registry()
  routes.register("hierarchical_substitution",{construct=patch,validate=function(x)
    return #x.tiling.cells==x.certificate.selected_leaf_count and x.certificate.root_complex.hull_pairs>0
  end})
  return routes
end
local function validate(x)
  local e=x.extensions.spectre
  local routes=provider()
  assert(e.route=="hierarchical_substitution" and P.serialize(e.capabilities)==P.serialize(routes.capabilities()),
    "spectre-route-certificate")
  local t=x.structures.tiling
  local vertices={}
  for _,v in ipairs(t.vertices) do vertices[v.id]=v.lattice end
  for _,c in ipairs(t.cells) do
    assert(c.chirality==1 and c.isometry.reflection==false and c.exact_transform.reflected==false,
      "spectre-illicit-reflected-leaf")
  end
  for _,edge in ipairs(t.edges) do
    if e.request.boundary=="spectre-s" then
      local a,b=controls(vertices[edge.from],vertices[edge.to])
      local q=edge.curve
      assert(q and q.denominator==192 and same(q.control1,a) and same(q.control2,b),"spectre-incorrectly-paired-curve")
    else
      assert(not edge.curve,"spectre-straight-diagnostic-curve")
    end
  end
  assert(P.serialize(e.request.frame)==P.serialize(x.frame),"spectre-fixed-frame")
  local result=routes.construct(e.route,P.plain(e.request))
  assert(P.serialize(result.tiling)==P.serialize(t),"spectre-source-hierarchy-reconstruction")
  assert(P.serialize(result.certificate)==P.serialize(e.certificate),"spectre-source-certificate")
  return {ok=true,checks=P.plain(e.certificate.checks),construction=P.plain(e.certificate)}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end

local palette={
  Gamma1={.74,.52,.30},Gamma2={.85,.68,.36},Delta={.34,.58,.58},Theta={.64,.43,.38},
  Lambda={.50,.55,.74},Xi={.31,.49,.64},Pi={.64,.70,.64},Sigma={.46,.61,.43},Phi={.57,.58,.72},Psi={.76,.67,.55},
}
local function lower(x,v,style)
  for k in pairs(style) do assert(k=="stroke_width" or k=="display","spectre-style:"..k) end
  local display=style.display or "lineage"
  assert(display=="lineage" or display=="uniform","spectre-display")
  local width=style.stroke_width or .010
  assert(finite(width) and width>0 and width<.1,"spectre-stroke-width")
  local G=require("pattern_geometry")
  local request=x.extensions.spectre.request
  local origin=request.frame.origin
  local step=request.step_cm
  local m=P.plain(v.transform)
  local crop=v.crop
  if not request.whole_root then
    local inverse=G.inverse(m,G.policy("cm",step))
    local q=request.world_query
    for _,corner in ipairs{{crop[1],crop[2]},{crop[3],crop[2]},{crop[3],crop[4]},{crop[1],crop[4]}} do
      local a=G.transform(corner,inverse)
      assert(a[1]>=q[1]-1e-10 and a[1]<=q[3]+1e-10 and a[2]>=q[2]-1e-10 and a[2]<=q[4]+1e-10,
        "spectre-view-outside-query")
    end
  end
  local function world_control(p)
    local a=xy(p,192)
    return {origin[1]+step*a[1],origin[2]+step*a[2]}
  end
  local points,edges,ops={},{},{}
  local tiling=x.structures.tiling
  for _,a in ipairs(tiling.vertices) do points[a.id]=a.point end
  local function expand(box,p)
    local a=G.transform(p,m)
    box[1],box[2]=math.min(box[1],a[1]),math.min(box[2],a[2])
    box[3],box[4]=math.max(box[3],a[1]),math.max(box[4],a[2])
  end
  local function empty_box() return {math.huge,math.huge,-math.huge,-math.huge} end
  for _,e in ipairs(tiling.edges) do
    local a,b=points[e.from],points[e.to]
    local q={a=a,b=b,box=empty_box()}
    expand(q.box,a);expand(q.box,b)
    if e.curve then
      q.c1,q.c2=world_control(e.curve.control1),world_control(e.curve.control2)
      expand(q.box,q.c1);expand(q.box,q.c2)
    end
    edges[e.id]=q
  end
  local function append(commands,e,reversed)
    local b=reversed and e.a or e.b
    if e.c1 then
      local p,q=e.c1,e.c2
      if reversed then p,q=q,p end
      commands[#commands+1]={"C",p[1],p[2],q[1],q[2],b[1],b[2]}
    else commands[#commands+1]={"L",b[1],b[2]} end
  end
  for _,c in ipairs(tiling.cells) do
    local b=empty_box()
    for _,use in ipairs(c.boundary) do
      local e=edges[use.edge].box
      b[1],b[2]=math.min(b[1],e[1]),math.min(b[2],e[2])
      b[3],b[4]=math.max(b[3],e[3]),math.max(b[4],e[4])
    end
    if meet(b,crop,0) then
      local use=c.boundary[1]
      local edge=edges[use.edge]
      local a=use.reversed and edge.b or edge.a
      local commands={{"M",a[1],a[2]}}
      for _,u in ipairs(c.boundary) do append(commands,edges[u.edge],u.reversed) end
      commands[#commands+1]={"Z"}
      ops[#ops+1]={op="path",semantic_ref=c.id,commands=commands,transform=m,
        paint={fill=display=="lineage" and palette[c.lineage_label] or {.67,.74,.78}}}
    end
  end
  local pad=width*math.sqrt(m[1]^2+m[2]^2+m[3]^2+m[4]^2)
  for _,e in ipairs(tiling.edges) do
    local q=edges[e.id]
    if meet(q.box,crop,pad) then
      local commands={{"M",q.a[1],q.a[2]}}
      append(commands,q,false)
      ops[#ops+1]={op="path",semantic_ref=e.id,commands=commands,transform=m,
        paint={stroke={.08,.15,.21},stroke_width=width}}
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end

function M.register(registry)
  local d=M.definition()
  local r=provider()
  registry:register(d,{generate=function(s,c)
    local p=s.parameters
    local request={depth=p.depth,root=p.root or "Gamma",step_cm=p.edge_length,boundary=p.boundary or "spectre-s",
      whole_root=p.whole_root or false,halo=p.halo or 4,frame=P.plain(c.frame),world_query=P.plain(s.document.bounds)}
    local result=r.construct("hierarchical_substitution",request,c)
    return {id=result.prefix.."/query/"..H.value("spectre/finite-view-selection",request),
      definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={tiling=result.tiling},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={spectre={route="hierarchical_substitution",request=request,certificate=result.certificate,
        capabilities=P.plain(r.capabilities())}}}
  end,validate=validate,lower=lower})
  return d
end
return M
