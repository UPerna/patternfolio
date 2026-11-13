-- Euclidean polygons in contact. See Kaplan (2005), sections 3 and 4.
local P = require("pattern")
local N = require("pattern_predicates")
local M = {}
local function sub(a,b) return {a[1]-b[1],a[2]-b[2]} end
local function add(a,b,k) return {a[1]+k*b[1],a[2]+k*b[2]} end
local function det(a,b) return a[1]*b[2]-a[2]*b[1] end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2] end
local function norm(a) return math.sqrt(dot(a,a)) end
local function unit(a)
  local length=norm(a)
  assert(length>0,"pic-zero-edge")
  return {a[1]/length,a[2]/length}
end
local function midpoint(a,b) return add(a,sub(b,a),.5) end
local function number(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function inside(p,polygon,tolerance)
  for i,a in ipairs(polygon) do
    local edge=sub(polygon[i%#polygon+1],a)
    if det(edge,sub(p,a)) < -tolerance*norm(edge) then return false end
  end
  return true
end
local function assert_convex(polygon)
  assert(type(polygon)=="table" and #polygon>=3 and #polygon<=24,"pic-polygon-size")
  for _,p in ipairs(polygon) do
    assert(type(p)=="table" and number(p[1]) and number(p[2]),"pic-polygon-coordinate")
  end
  for i,a in ipairs(polygon) do
    local b=polygon[i%#polygon+1]
    for j,p in ipairs(polygon) do
      if j~=i and j~=i%#polygon+1 then
        assert(N.orient2d(a,b,p)>0,"pic-strict-convex-ccw")
      end
    end
  end
end

-- An optional angle callback supplies already established contact geometry
-- from neighboring motifs, as in Kaplan and Salesin's Euclidean gap inference.
function M.motif(polygon,angle,displacement,contact_angle,contact_direction)
  assert_convex(polygon)
  assert(number(displacement) and displacement>=0,"pic-displacement")
  local rays,pairs_,used,segments={},{},{},{}
  local scale=0
  for i,a in ipairs(polygon) do
    local b=polygon[i%#polygon+1]
    local edge=sub(b,a)
    local length=norm(edge)
    assert(displacement<length,"pic-displacement-reaches-edge-end")
    scale=math.max(scale,length)
    local theta=contact_angle and contact_angle(i) or angle
    assert(number(theta) and theta>0 and theta<90,"pic-contact-angle")
    local t=unit(edge)
    local c,s=math.cos(theta*math.pi/180),math.sin(theta*math.pi/180)
    for _,side in ipairs{-1,1} do
      local direction={side*c*t[1]-s*t[2],side*c*t[2]+s*t[1]}
      local actual=contact_direction and contact_direction(i,side)
      local measured=theta
      if actual then
        direction=unit(actual)
        assert(det(t,direction)>0,"pic-contact-direction-outward")
        measured=math.deg(math.atan(math.abs(det(t,direction)),math.abs(dot(t,direction))))
      end
      rays[#rays+1]={edge=i,side=side,origin=add(midpoint(a,b),t,-side*displacement/2),
        direction=direction,angle=measured}
    end
  end
  local tolerance=scale*1e-10
  for i,a in ipairs(rays) do
    for j=i+1,#rays do
      local b=rays[j]
      if a.edge~=b.edge then
        local between=sub(b.origin,a.origin)
        local denominator=det(a.direction,b.direction)
        local point,cost,kind
        if math.abs(denominator)>1e-12 then
          local ta,tb=det(between,b.direction)/denominator,det(between,a.direction)/denominator
          if ta>tolerance and tb>tolerance then
            point=add(a.origin,a.direction,ta)
            if inside(point,polygon,tolerance) then cost,kind=ta+tb,"intersection" end
          end
        elseif math.abs(det(between,a.direction))<=tolerance
          and dot(a.direction,b.direction)<0 and dot(between,a.direction)>tolerance then
          point,cost,kind=midpoint(a.origin,b.origin),norm(between),"opposing_collinear"
        end
        if cost then
          pairs_[#pairs_+1]={first=i,second=j,point=point,cost=cost,kind=kind,
            rank=math.floor(cost/tolerance+.5)}
        end
      end
    end
  end
  table.sort(pairs_,function(a,b)
    if a.rank~=b.rank then return a.rank<b.rank end
    if a.first~=b.first then return a.first<b.first end
    return a.second<b.second
  end)
  for _,p in ipairs(pairs_) do
    if not used[p.first] and not used[p.second] then
      used[p.first],used[p.second]=true,true
      p.rank=nil
      segments[#segments+1]=p
    end
  end
  for i,r in ipairs(rays) do
    assert(used[i],"pic-unmatched-ray:"..r.edge.."/"..r.side)
  end
  return {rays=rays,paths=segments}
end

function M.rosette_inset(polygon,ratio)
  assert_convex(polygon)
  local n=#polygon
  assert(n>=5,"pic-rosette-needs-five-sides")
  ratio=ratio or 1
  assert(number(ratio) and ratio>0,"pic-rosette-ratio")
  local center={0,0}
  for _,p in ipairs(polygon) do center=add(center,p,1/n) end
  local radius=norm(sub(polygon[1],center))
  local length=norm(sub(polygon[2],polygon[1]))
  local alpha=math.pi/n
  local inset_radius=ratio*radius*(math.cos(alpha)-math.sin(alpha)*math.tan(math.pi*(n-2)/(4*n)))
  assert(inset_radius>0 and inset_radius<radius*math.cos(alpha),"pic-rosette-inset-outside")
  local vertices,spokes={},{}
  for i,p in ipairs(polygon) do
    local q=polygon[i%n+1]
    assert(math.abs(norm(sub(p,center))-radius)<=radius*1e-9 and math.abs(norm(sub(q,p))-length)<=length*1e-9,
      "pic-rosette-requires-regular-polygon")
    local edge_mid=midpoint(p,q)
    local inner=add(center,unit(sub(edge_mid,center)),inset_radius)
    vertices[i]=inner
    spokes[i]={from=inner,to=edge_mid}
  end
  return {center=center,radius=radius,inset_radius=inset_radius,vertices=vertices,spokes=spokes}
end

-- Translate stage 09 cell boundaries into CCW faces with shared vertex IDs.
function M.faces(tiling)
  local vertices,edges,faces={},{},{}
  for _,v in ipairs(tiling.vertices) do vertices[v.id]=P.plain(v.point) end
  for _,e in ipairs(tiling.edges) do edges[e.id]=e end
  for _,cell in ipairs(tiling.cells) do
    local face={id=cell.id,vertices={},prototype=cell.prototype}
    for _,use in ipairs(cell.boundary) do
      local e=edges[use.edge]
      face.vertices[#face.vertices+1]=use.reversed and e.to or e.from
    end
    faces[#faces+1]=face
  end
  return vertices,faces
end

local function points(ids,vertices)
  local p={}
  for i,id in ipairs(ids) do p[i]=assert(vertices[id],"pic-missing-scaffold-vertex") end
  return p
end
local function edge_id(a,b)
  if P.byte_less(b,a) then return b.."+"..a end
  return a.."+"..b
end

-- The original sides disappear. The bounded transformed patch keeps inset
-- octagons and complete vertex fans, leaving only outer-patch boundary ports.
function M.rosette_patch(vertices,faces,ratio)
  local out,transformed,fans,lineage={},{},{},{}
  for _,face in ipairs(faces) do
    local poly=points(face.vertices,vertices)
    local anchors={}
    if #poly==8 then
      local inset=M.rosette_inset(poly,ratio)
      local id="inset/"..face.id
      for i,p in ipairs(inset.vertices) do
        anchors[i]=id.."/v"..i
        out[anchors[i]]=p
      end
      transformed[#transformed+1]={id=id,vertices=anchors,prototype="inset-octagon"}
      lineage[id]={parent=face.id,kind="regular-inset",radius=inset.radius,inset_radius=inset.inset_radius}
    elseif #poly==4 then
      assert_convex(poly)
      local a,b,c,d=table.unpack(poly)
      local center=midpoint(a,c)
      assert(norm(sub(center,midpoint(b,d)))<1e-10 and
        math.abs(dot(sub(b,a),sub(d,a)))<1e-10 and math.abs(norm(sub(b,a))-norm(sub(d,a)))<1e-10,
        "pic-rosette-square-bisectors")
      local id="bisectors/"..face.id
      out[id]=center
      for i=1,4 do anchors[i]=id end
    else
      error("pic-rosette-unsupported-scaffold")
    end
    for i,vertex in ipairs(face.vertices) do
      local fan=fans[vertex]
      if not fan then fan={anchors={},parents={},octagons=0};fans[vertex]=fan end
      fan.parents[#fan.parents+1]=face.id
      if #poly==8 then fan.octagons=fan.octagons+1 end
      fan.anchors[anchors[i]]=true
      fan.anchors[anchors[(i-2)%#poly+1]]=true
    end
  end
  local keys={}
  for k in pairs(fans) do keys[#keys+1]=k end
  table.sort(keys,P.byte_less)
  for _,v in ipairs(keys) do
    local fan=fans[v]
    if #fan.parents==3 and fan.octagons==2 then
      local center=vertices[v]
      local ring={}
      for a in pairs(fan.anchors) do ring[#ring+1]=a end
      table.sort(ring,function(a,b)
        local u,w=sub(out[a],center),sub(out[b],center)
        return math.atan(u[2],u[1])<math.atan(w[2],w[1])
      end)
      assert(#ring==5,"pic-rosette-pentagon-incidence")
      assert_convex(points(ring,out))
      local id="fan/"..v
      table.sort(fan.parents,P.byte_less)
      transformed[#transformed+1]={id=id,vertices=ring,prototype="vertex-pentagon"}
      lineage[id]={parents=fan.parents,vertex=v,kind="bisector-fan"}
    else
      assert(#fan.parents<3,"pic-rosette-unexpected-vertex-fan")
    end
  end
  return out,transformed,lineage
end

-- A motif vertex is either an interior bend or a branch at a shared edge.
-- Zero displacement keeps two coincident positions as distinct strands.
function M.assemble(vertices,faces,angle,displacement,gradient)
  local nodes,links,motifs,ports,degree={},{},{},{},{}
  local function vertex(id,p)
    local existing=nodes[id]
    if existing then
      assert(norm(sub(existing,p))<1e-9,"pic-seam-position-mismatch")
    else nodes[id]=p end
  end
  local function join(id,a,b,face)
    assert(a~=b and norm(sub(nodes[a],nodes[b]))>1e-10,"pic-zero-link")
    links[#links+1]={id=id,from=a,to=b,face=face}
    degree[a]=(degree[a]or 0)+1
    degree[b]=(degree[b]or 0)+1
  end
  for _,f in ipairs(faces) do
    local polygon=points(f.vertices,vertices)
    local function angle_at(i)
      local a,b=polygon[i],polygon[i%#polygon+1]
      return angle+(gradient or 0)*midpoint(a,b)[1]
    end
    local motif=M.motif(polygon,angle,displacement,angle_at)
    motifs[f.id]=motif
    for _,r in ipairs(motif.rays) do
      local a,b=f.vertices[r.edge],f.vertices[r.edge%#polygon+1]
      local reversed=P.byte_less(b,a)
      local side=(displacement==0 or not reversed) and r.side or -r.side
      local key=edge_id(a,b).."/"..(side==1 and "plus" or "minus")
      local id="contact/"..key
      vertex(id,r.origin)
      r.port=id
      local p=ports[id]
      if not p then p={point=nodes[id],direction=r.direction,angle=r.angle,faces={f.id}};ports[id]=p
      else
        assert(#p.faces==1 and math.abs(p.angle-r.angle)<1e-10,"pic-seam-angle-or-incidence")
        local direction=p.direction
        if displacement>0 then
          local tangent=unit(sub(vertices[b],vertices[a]))
          direction=add({-direction[1],-direction[2]},tangent,2*dot(direction,tangent))
        else direction={-direction[1],-direction[2]} end
        assert(norm(sub(direction,r.direction))<1e-9,"pic-seam-direction-mismatch")
        p.faces[2]=f.id
      end
    end
    for i,path in ipairs(motif.paths) do
      local a,b=motif.rays[path.first].port,motif.rays[path.second].port
      local key=f.id.."/"..i
      local id="bend/"..key
      vertex(id,path.point)
      join("path/"..key.."/a",a,id,f.id)
      join("path/"..key.."/b",id,b,f.id)
    end
  end
  for id,p in pairs(ports) do
    assert(degree[id]==#p.faces and degree[id]<=2,"pic-seam-degree")
    p.role=degree[id]==2 and "interior" or "patch_boundary"
  end
  return {nodes=nodes,links=links,motifs=motifs,ports=ports}
end

local function sorted_keys(t)
  local keys={}
  for k in pairs(t) do keys[#keys+1]=k end
  table.sort(keys,P.byte_less)
  return keys
end
local function summarize(graph)
  local vertices,contacts=P.array(),P.array()
  for _,id in ipairs(sorted_keys(graph.nodes)) do
    vertices[#vertices+1]={id=id,point=graph.nodes[id]}
  end
  for _,id in ipairs(sorted_keys(graph.ports)) do
    local p=graph.ports[id]
    contacts[#contacts+1]={id=id,faces=p.faces,angle=p.angle,direction=p.direction,role=p.role}
  end
  return {vertices=vertices,edges=graph.links},contacts
end

function M.definition()
  return P.definition({id="ornament/islamic-pic",version="1",family="euclidean-polygons-in-contact",
    units="cm",capabilities={"graph"},parameters={
      scaffold={type="string",enum={"square","hexagonal","4.8.8","4.6.12"},required=true},
      contact_angle={type="number",minimum=1,maximum=89,required=true},
      displacement={type="number",minimum=0,maximum=10},
      lattice_step={type="number",minimum=.25,maximum=20,required=true},
      rotation={type="number",minimum=-360,maximum=360},
      parquet_gradient={type="number",minimum=-15,maximum=15},
      rosette_ratio={type="number",minimum=.5,maximum=1.5}},
    transforms={metric_constrained=true,uniform_scale=true,reflection=false},
    assumptions={"Euclidean only, strict convex faces and complete greedy pairing",
      "Scaffold contact IDs and ornament graph are separate. Crop does not regenerate geometry.",
      "Midpoint branch crossings are undecorated. No over/under paint order is claimed."}})
end

local function validate(x)
  local k=x.extensions.pic
  local graph=M.assemble(P.plain(k.scaffold_vertices),P.plain(k.scaffold_faces),k.contact_angle,k.displacement,k.parquet_gradient)
  local structure,ports=summarize(graph)
  assert(P.serialize(structure)==P.serialize(x.structures.graph),"pic-graph-reconstruction")
  assert(P.serialize(ports)==P.serialize(k.contacts),"pic-contact-reconstruction")
  if k.rosette then
    local vertices,faces,lineage=M.rosette_patch(P.plain(k.rosette.original_vertices),P.plain(k.rosette.original_faces),k.rosette.ratio)
    assert(P.serialize(vertices)==P.serialize(k.scaffold_vertices) and P.serialize(faces)==P.serialize(k.scaffold_faces)
      and P.serialize(lineage)==P.serialize(k.rosette.lineage),"pic-rosette-reconstruction")
  end
  return {ok=true,checks={"source greedy ray pairs and incidence","seam branch and shared angle consistency","rosette lineage reconstruction"}}
end

function M.validate(instance) return validate(P.instance(P.plain(instance),M.definition())) end

local function lower(x,v,style)
  for k in pairs(style) do assert(k=="stroke" or k=="stroke_width","pic-unsupported-style:"..k) end
  local width=style.stroke_width or .024
  assert(number(width) and width>0 and width<=.3,"pic-stroke-width")
  local G=require("pattern_geometry")
  local matrix=P.plain(v.transform)
  local crop=v.crop
  local world,page,ops={},{},{}
  for _,n in ipairs(x.structures.graph.vertices) do
    world[n.id]=n.point
    page[n.id]=G.transform(n.point,matrix)
  end
  local pad=width*math.sqrt(matrix[1]^2+matrix[2]^2+matrix[3]^2+matrix[4]^2)
  for _,e in ipairs(x.structures.graph.edges) do
    local a,b=page[e.from],page[e.to]
    if math.min(a[1],b[1])-pad<=crop[3] and math.max(a[1],b[1])+pad>=crop[1]
      and math.min(a[2],b[2])-pad<=crop[4] and math.max(a[2],b[2])+pad>=crop[2] then
      local p,q=world[e.from],world[e.to]
      ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",p[1],p[2]},{"L",q[1],q[2]}},
        transform=matrix,paint={stroke=style.stroke or {.13,.29,.49},stroke_width=width}}
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end

M.lower_graph=lower

function M.register(registry)
  local R,T=require("pattern_registry"),require("pattern_periodic")
  local base=R.new()
  local periodic=T.register(base)
  local definition=M.definition()
  local function generate(s,c)
    local a=s.parameters
    if a.rosette_ratio then assert(a.scaffold=="4.8.8","pic-rosette-requires-4.8.8") end
    local scaffold=P.specification({id=s.id.."/scaffold",definition_ref={id=periodic.id,version=periodic.version},
      seed=s.seed,parameters={family=a.scaffold,lattice_step=a.lattice_step,rotation_degrees=a.rotation},
      inputs={},constraints={},style={},budget=P.plain(s.budget),document=P.plain(s.document)},periodic)
    local request,reason=base:generate(periodic.id,scaffold,c)
    assert(request,reason and P.serialize(reason))
    local vertices,faces=M.faces(request.instance.structures.tiling)
    local rosette
    if a.rosette_ratio then
      local source_vertices,source_faces=vertices,faces
      local lineage
      vertices,faces,lineage=M.rosette_patch(vertices,faces,a.rosette_ratio)
      rosette={original_vertices=source_vertices,original_faces=source_faces,lineage=lineage,ratio=a.rosette_ratio}
    end
    assert(#faces<=360,"pic-face-budget")
    for _,face in ipairs(faces) do
      c:consume("operations",4*(#face.vertices)^2)
      c:consume("objects",8*#face.vertices)
    end
    local delta,gradient=a.displacement or 0,a.parquet_gradient or 0
    local graph,contacts=summarize(M.assemble(vertices,faces,a.contact_angle,delta,gradient))
    return {id=s.id.."/pic",definition_ref={id=definition.id,version=definition.version},frame=P.plain(c.frame),
      structures={graph=graph},provenance={generator=definition.id,generator_version=definition.version,seed=s.seed,
        construction="kaplan-pic-euclidean-v1"},
      extensions={pic={scaffold_vertices=vertices,scaffold_faces=faces,contacts=contacts,contact_angle=a.contact_angle,
        displacement=delta,parquet_gradient=gradient,rosette=rosette}}}
  end
  registry:register(definition,{generate=generate,validate=validate,lower=lower})
  return definition
end

return M
