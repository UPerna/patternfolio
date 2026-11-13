-- Globally anchored, edge-to-edge periodic constructions. Query bounds select
-- integer addresses; they never become the coordinate origin or assign IDs.
local P,H,G=require("pattern"),require("pattern_hash"),require("pattern_geometry")
local T,W=require("pattern_periodic_templates"),require("pattern_wallpaper")
local M={VERSION="periodic-lattice-v1"}
local function finite(n)return type(n)=="number"and n==n and math.abs(n)<math.huge end
local function cell_id(prefix,i,j,name)return prefix.."/c/"..i.."/"..j.."/"..name end
local function point_id(prefix,p)return prefix.."/v/"..T.key(p)end
local function edge_id(prefix,a,b)return prefix.."/e/"..T.key(a)..":"..T.key(b)end
local function linear(m,p)
  return{m[1]*p[1]+m[2]*p[3],m[1]*p[2]+m[2]*p[4],m[3]*p[1]+m[4]*p[3],m[3]*p[2]+m[4]*p[4]}
end
local function chart(t,step,degrees,origin)
  assert(finite(step)and step>=0.25 and step<=20,"lattice step must be0.25..20cm")
  assert(finite(degrees),"finite lattice angle required");degrees=degrees%360
  local c,s
  if degrees==0 then c,s=1,0 elseif degrees==90 then c,s=0,1 elseif degrees==180 then c,s=-1,0 elseif degrees==270 then c,s=0,-1
  else local a=degrees*math.pi/180;c,s=math.cos(a),math.sin(a)end
  local bx,by=t.lattice=="hexagonal"and step/2 or 0,t.lattice=="hexagonal"and step*math.sqrt(3)/2 or step
  assert(math.abs(origin[1])<=1e6 and math.abs(origin[2])<=1e6,"periodic origin exceeds admitted cm frame")
  return {c*step,s*step,c*bx-s*by,s*bx+c*by,origin[1],origin[2]},degrees
end
local function frame_identity(t,step,angle,frame)
  return "periodic/"..H.value("periodic/frame-v1",{family=t.id,step=step,angle=angle,frame=P.plain(frame)})
end
local function world(t,m,p)return G.transform(T.point_value(p,t.radicand),m)end
local function bounds_corners(b)return{{b[1],b[2]},{b[3],b[2]},{b[3],b[4]},{b[1],b[4]}}end
local function query_range(t,m,bounds)
  local inv=G.inverse(m,G.policy("cm",1));local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,p in ipairs(bounds_corners(bounds))do local q=G.transform(p,inv)
    x0,y0,x1,y1=math.min(x0,q[1]),math.min(y0,q[2]),math.max(x1,q[1]),math.max(y1,q[2])
  end
  -- Extra integer rings provide strict margin even at floating inverse bounds.
  local s=t.support
  local r={math.floor(x0-s[3])-1,math.floor(y0-s[4])-1,math.ceil(x1-s[1])+1,math.ceil(y1-s[2])+1}
  for _,n in ipairs(r)do assert(math.abs(n)<=32768,"periodic lattice address exceeds bounded profile")end
  assert((r[3]-r[1]+1)*(r[4]-r[2]+1)*#t.faces<=1536,"periodic query exceeds1536 complete cells; use a smaller bounded window")
  return r
end
local function motif_signature(f,m)
  local c=linear(m,f.center);assert(c[2]==0 and c[4]==0,"prototype center must have rational lattice coordinates")
  local i,j=c[1]//6,c[3]//6;local keys={}
  for _,p in ipairs(f.vertices)do keys[#keys+1]=T.key(T.shift(linear(m,p),-i,-j))end
  table.sort(keys,P.byte_less);return f.prototype..":"..table.concat(keys,":"),i,j
end
local function group_actions(t,group)
  local lookup,out={},{}
  for _,f in ipairs(t.faces)do local k,i,j=motif_signature(f,{1,0,0,1});assert(not lookup[k],"duplicate cell under translation");lookup[k]={id=f.id,i=i,j=j}end
  for _,op in ipairs(group.operations)do
    local maps={}
    for _,f in ipairs(t.faces)do
      local key,i,j=motif_signature(f,op.matrix);local to=assert(lookup[key],"declared group does not preserve the actual tiling templates")
      maps[#maps+1]={from=f.id,to=to.id,offset={i-to.i,j-to.j},orientation=op.orientation}
    end
    out[#out+1]={operation=op.id,prototype_maps=maps}
  end
  return out
end
local function gcd(a,b)while b~=0 do a,b=b,a%b end;return a end
local function port(e,a,b,num,denom)
  assert(type(num)=="number"and type(denom)=="number"and num%1==0 and denom%1==0 and num>0 and num<denom and denom<=4096,"port requires a bounded interior rational parameter")
  num,denom=math.tointeger(num),math.tointeger(denom);local k=gcd(num,denom);num,denom=num//k,denom//k
  local t=num/denom;local q={}
  for i=1,4 do q[i]=(denom-num)*a.lattice[i]+num*b.lattice[i]end
  return{id=e.id.."/port/"..num.."/"..denom,edge_ref=e.id,parameter={num,denom},
    point={a.point[1]+t*(b.point[1]-a.point[1]),a.point[2]+t*(b.point[2]-a.point[2])},
    lattice=q,lattice_denominator=6*denom}
end
function M.port(instance,cell_ref,boundary_index,numerator,denominator)
  assert(type(numerator)=="number"and type(denominator)=="number","port requires a rational parameter")
  local t=instance.structures.tiling;local cell
  for _,c in ipairs(t.cells)do if c.id==cell_ref then cell=c;break end end
  local use=assert(cell and cell.boundary[boundary_index],"missing tile boundary use")
  local e,a,b
  for _,edge in ipairs(t.edges)do if edge.id==use.edge then e=edge;break end end
  assert(e,"missing shared edge")
  for _,v in ipairs(t.vertices)do if v.id==e.from then a=v elseif v.id==e.to then b=v end;if a and b then break end end
  assert(a and b,"missing port endpoints")
  return P.snapshot(port(e,a,b,use.reversed and denominator-numerator or numerator,denominator))
end
local function generate(d,s,c)
  assert(c.frame.dimension==2 and c.frame.unit=="cm","periodic construction requires a2D cm frame")
  assert(not c.planning or c.planning.mode=="fixed_frame","periodic construction requires a fixed world frame")
  local t=T.get(s.parameters.family);local step=s.parameters.lattice_step
  local matrix,angle=chart(t,step,s.parameters.rotation_degrees or 0,G.point(c.frame.origin))
  local group=W.group(s.parameters.wallpaper or(t.lattice=="square"and"p4m"or"p6m"),t.lattice)
  local actions=group_actions(t,group);local r=query_range(t,matrix,s.document.bounds)
  local prefix=frame_identity(t,step,angle,c.frame)
  local vertices,edges,cells,vm,em={},{},{},{},{}
  local function vertex(q)
    local id=point_id(prefix,q)
    if not vm[id]then c:consume("objects",1);local v={id=id,point=world(t,matrix,q),lattice=q};vm[id]=v;vertices[#vertices+1]=v end
    return vm[id]
  end
  for j=r[2],r[4]do for i=r[1],r[3]do for _,f in ipairs(t.faces)do
    c:consume("objects",1)
    local id=cell_id(prefix,i,j,f.id)
    local cell={id=id,prototype=f.prototype,chirality=1,template=f.id,address={i,j},
      isometry={rotation_degrees=(angle+f.rotation_degrees)%360,reflection=false,center=world(t,matrix,T.shift(f.center,i,j))},boundary={}}
    cells[#cells+1]=cell
    for k,q in ipairs(f.vertices)do
      c:consume("operations",1)
      local a,b=vertex(T.shift(q,i,j)),vertex(T.shift(f.vertices[k%#f.vertices+1],i,j))
      local reversed=P.byte_less(b.id,a.id);if reversed then a,b=b,a end
      local eid=edge_id(prefix,a.lattice,b.lattice)
      local n=f.neighbors[k];local adjacent=cell_id(prefix,i+n.offset[1],j+n.offset[2],n.template)
      local owner=P.byte_less(adjacent,id)and adjacent or id
      if not em[eid]then
        c:consume("objects",1)
        local e={id=eid,from=a.id,to=b.id,owner=id,role="patch_boundary",global_owner=owner,
          equivalence=n.class,global_cells=P.byte_less(id,adjacent)and{id,adjacent}or{adjacent,id}}
        e.midpoint=port(e,a,b,1,2);em[eid]=e;edges[#edges+1]=e
      else
        local e=em[eid];assert(e.role=="patch_boundary"and e.global_owner==owner and e.equivalence==n.class,"periodic edge has inconsistent neighbors")
        e.role="interior";e.owner=e.global_owner
      end
      cell.boundary[#cell.boundary+1]={edge=eid,reversed=reversed,neighbor=adjacent,neighbor_edge=n.edge,port_ref=em[eid].midpoint.id}
    end
  end end end
  local period={profile=M.VERSION,template=t.id,frame_identity=prefix,step_cm=step,rotation_degrees=angle,basis={{matrix[1],matrix[2]},{matrix[3],matrix[4]}},
    lattice=t.lattice,radicand=t.radicand,lattice_denominator=6,matrix=matrix,integer_query=r,
    world_query=P.plain(s.document.bounds),translation_domain=
      {G.transform({0,0},matrix),G.transform({1,0},matrix),G.transform({1,1},matrix),G.transform({0,1},matrix)},
    wallpaper=P.plain(group),group_actions=actions,coverage_certificate=P.plain(t.certificate),declared_periodic=true}
  return{id=prefix.."/patch/"..group.id.."/"..table.concat(r,"/"),definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),
    structures={tiling={vertices=vertices,edges=edges,cells=cells}},
    provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},extensions={periodic=period}}
end
local function validate(x,c)
  local p=x.extensions.periodic;local t=T.get(p.template);local r=p.integer_query;local a=x.structures.tiling
  assert(p.profile==M.VERSION and p.lattice==t.lattice and p.radicand==t.radicand and p.lattice_denominator==6,"wrong exact lattice profile")
  local m,angle=chart(t,p.step_cm,p.rotation_degrees,x.frame.origin)
  assert(P.serialize(m)==P.serialize(p.matrix)and angle==p.rotation_degrees,"invalid periodic metric frame")
  local prefix=frame_identity(t,p.step_cm,angle,x.frame);assert(prefix==p.frame_identity,"unstable periodic frame identity")
  assert(P.serialize(query_range(t,m,p.world_query))==P.serialize(r),"stale integer query extent")
  local domain={G.transform({0,0},m),G.transform({1,0},m),G.transform({1,1},m),G.transform({0,1},m)}
  assert(P.serialize(domain)==P.serialize(p.translation_domain)and P.serialize(p.basis)==P.serialize({{m[1],m[2]},{m[3],m[4]}}),"wrong translation fundamental domain or basis")
  local group=W.group(p.wallpaper.id,t.lattice)
  assert(x.id==prefix.."/patch/"..group.id.."/"..table.concat(r,"/"),"wrong periodic instance identity")
  assert(P.serialize(group)==P.serialize(p.wallpaper)and P.serialize(group_actions(t,group))==P.serialize(p.group_actions),"forged symmetry operations or prototype maps")
  assert(p.declared_periodic and P.serialize(t.certificate)==P.serialize(p.coverage_certificate),"invalid periodic coverage proof")
  assert(#a.cells==(r[3]-r[1]+1)*(r[4]-r[2]+1)*#t.faces,"incomplete integer query")
  local vs,es,fs,cs,used={},{},{},{},{}
  for _,f in ipairs(t.faces)do fs[f.id]=f end
  for _,v in ipairs(a.vertices)do
    assert(#v.lattice==4,"expected four exact lattice coefficients");for _,n in ipairs(v.lattice)do assert(type(n)=="number"and n%1==0 and math.abs(n)<=196620,"invalid exact lattice coefficient")end
    assert(v.id==point_id(prefix,v.lattice)and P.serialize(v.point)==P.serialize(world(t,m,v.lattice)),"vertex differs from its exact lattice address");vs[v.id]=v
  end
  for _,e in ipairs(a.edges)do
    assert(e.id==edge_id(prefix,vs[e.from].lattice,vs[e.to].lattice)and P.byte_less(e.from,e.to),"wrong canonical edge direction")
    assert(P.serialize(port(e,vs[e.from],vs[e.to],1,2))==P.serialize(e.midpoint),"forged midpoint port");es[e.id]=e;used[e.from],used[e.to]=true,true
  end
  for _,v in ipairs(a.vertices)do assert(used[v.id],"unused vertex in complete periodic query")end
  for _,cell in ipairs(a.cells)do cs[cell.id]=cell end
  for _,cell in ipairs(a.cells)do
    local i,j=cell.address[1],cell.address[2];local f=assert(fs[cell.template])
    assert(i%1==0 and j%1==0 and i>=r[1]and i<=r[3]and j>=r[2]and j<=r[4]and cell.id==cell_id(prefix,i,j,f.id),"unstable tile address")
    assert(cell.prototype==f.prototype and #cell.boundary==#f.vertices and cell.chirality==1,"wrong prototype/incidence")
    assert(cell.isometry.reflection==false and cell.isometry.rotation_degrees==(angle+f.rotation_degrees)%360 and
      P.serialize(cell.isometry.center)==P.serialize(world(t,m,T.shift(f.center,i,j))),"unexpected tile isometry")
    for k,use in ipairs(cell.boundary)do
      c:consume("operations",1)
      local e=es[use.edge];local v1,v2=use.reversed and e.to or e.from,use.reversed and e.from or e.to
      assert(v1==point_id(prefix,T.shift(f.vertices[k],i,j))and v2==point_id(prefix,T.shift(f.vertices[k%#f.vertices+1],i,j)),"tile does not follow its exact edge walk")
      local n=f.neighbors[k];local adj=cell_id(prefix,i+n.offset[1],j+n.offset[2],n.template)
      local owner=P.byte_less(cell.id,adj)and cell.id or adj;local other=owner==cell.id and adj or cell.id
      assert(use.neighbor==adj and use.neighbor_edge==n.edge and use.port_ref==e.midpoint.id and e.equivalence==n.class and
        e.global_owner==owner and e.global_cells[1]==owner and e.global_cells[2]==other and #e.global_cells==2,"wrong global seam correspondence")
      assert((cs[adj]and e.role=="interior"and e.owner==owner)or(not cs[adj]and e.role=="patch_boundary"and e.owner==cell.id),"wrong finite-patch ownership")
    end
  end
  return{ok=true,checks={"exact translated prototype pairs; equal areas and no positive interior overlaps","stable global vertex/cell IDs and theoretical edge owners","actual directed shared incidence and rational midpoint ports","metric-preserving declared affine group actions"}}
end
local palette={square={0.84,0.69,0.35},triangle={0.22,0.48,0.69},hexagon={0.21,0.58,0.57},octagon={0.22,0.48,0.69},dodecagon={0.24,0.39,0.65}}
local function lower(x,v,style)
  for k in pairs(style)do assert(k=="stroke_width"or k=="stroke"or k=="fill"or k=="marker","unsupported periodic style "..k)end
  assert(style.marker==nil or type(style.marker)=="boolean","marker must be boolean")
  local t=x.structures.tiling;local world_points,page_points,es,ops={},{},{},{}
  local matrix=P.plain(v.transform);local stroke_width=style.stroke_width or 0.016
  assert(finite(stroke_width)and stroke_width>0,"positive periodic stroke width required")
  local crop=v.crop
  local function visible(x0,y0,x1,y1,pad)return x1+pad>=crop[1]and y1+pad>=crop[2]and x0-pad<=crop[3]and y0-pad<=crop[4]end
  for _,p in ipairs(t.vertices)do world_points[p.id]=p.point;page_points[p.id]=G.transform(p.point,matrix)end
  for _,e in ipairs(t.edges)do es[e.id]=e end
  for _,cell in ipairs(t.cells)do
    local cmd={};local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
    for k,use in ipairs(cell.boundary)do
      local e=es[use.edge];local id=use.reversed and e.to or e.from;local p,q=world_points[id],page_points[id]
      cmd[#cmd+1]={k==1 and"M"or"L",p[1],p[2]}
      x0,y0,x1,y1=math.min(x0,q[1]),math.min(y0,q[2]),math.max(x1,q[1]),math.max(y1,q[2])
    end
    if visible(x0,y0,x1,y1,0)then
      cmd[#cmd+1]={"Z"};ops[#ops+1]={op="path",semantic_ref=cell.id,commands=cmd,transform=matrix,paint={fill=style.fill or palette[cell.prototype]}}
      if style.marker then
        local a=cell.isometry.rotation_degrees*math.pi/180;local c,s=math.cos(a),math.sin(a);local o=cell.isometry.center
        local k=x.extensions.periodic.step_cm*0.08;local mark={}
        for i,p in ipairs({{-0.65,-0.35},{0.9,-0.12},{-0.35,0.65}})do
          mark[#mark+1]={i==1 and"M"or"L",o[1]+k*(c*p[1]-s*p[2]),o[2]+k*(s*p[1]+c*p[2])}
        end
        mark[#mark+1]={"Z"};ops[#ops+1]={op="path",semantic_ref=cell.id,commands=mark,transform=matrix,paint={fill={0.98,0.96,0.88}}}
      end
    end
  end
  local pad=stroke_width*math.sqrt(matrix[1]^2+matrix[2]^2+matrix[3]^2+matrix[4]^2)
  local edges={};for _,e in ipairs(t.edges)do edges[#edges+1]=e end
  table.sort(edges,function(a,b)return P.byte_less(a.id,b.id)end)
  for _,e in ipairs(edges)do
    local a,b=world_points[e.from],world_points[e.to];local aa,bb=page_points[e.from],page_points[e.to]
    if visible(math.min(aa[1],bb[1]),math.min(aa[2],bb[2]),math.max(aa[1],bb[1]),math.max(aa[2],bb[2]),pad)then
      ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",a[1],a[2]},{"L",b[1],b[2]}},transform=matrix,paint={stroke=style.stroke or{0.08,0.12,0.21},stroke_width=stroke_width}}
    end
  end
  return{id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end
function M.definition()
  return P.definition({id="tiling/periodic",version="1",family="periodic-lattice",units="cm",capabilities={"tiling"},parameters={
    family={type="string",enum=T.names(),required=true},lattice_step={type="number",minimum=0.25,maximum=20,required=true},
    rotation_degrees={type="number",minimum=-360,maximum=360},wallpaper={type="string",enum=W.names()}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Only explicit certified templates and declared symmorphic groups","Integer lattice identities, quadratic exact template geometry and binary64 world realization","Complete bounded queries; document crops do not regenerate source cells"}})
end
function M.validate(instance,context)
  return validate(P.instance(P.plain(instance),M.definition()),context)
end
function M.register(registry)
  local d=M.definition();registry:register(d,{generate=function(s,c)return generate(d,s,c)end,validate=validate,lower=lower});return d
end
function M.profile(definition,step)
  assert(finite(step)and step>=0.25 and step<=20,"invalid periodic lattice step")
  return require("pattern_planner").profile(definition,{mode="fixed_frame",construction_scale=math.max(1,step),maximum_tile_diameter=2.1*step})
end
return M
