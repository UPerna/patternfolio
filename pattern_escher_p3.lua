-- Kaplan thesis Figure 4.23 and Kaplan–Salesin Figure 6. Every
-- quasivertex lives in an integer chart of Q(zeta_20), not a snapped plane.
local P,G,H=require("pattern"),require("pattern_geometry"),require("pattern_hash")
local Metric=require("pattern_escher_metric")
local M={VERSION="p3-quasivertex-fig423-v1",DENOMINATOR=1024}
local D=M.DENOMINATOR
local function zero() return {0,0,0,0,0,0,0,0} end
local roots={{1,0,0,0,0,0,0,0}}
for j=2,20 do
  local a=roots[j-1]
  roots[j]={-a[8],a[1],a[2]+a[8],a[3],a[4]-a[8],a[5],a[6]+a[8],a[7]}
end
local function root(k) return roots[k%20+1] end
local function add(a,b)
  local out={}
  for i=1,8 do out[i]=a[i]+b[i] end
  return out
end
local function scale(a,k)
  local out={}
  for i=1,8 do out[i]=a[i]*k end
  return out
end
local function sub(a,b) return add(a,scale(b,-1)) end
local function rotate(a,k)
  local out=zero()
  for i=1,8 do
    if a[i]~=0 then
      local r=root(i-1+k)
      for j=1,8 do out[j]=out[j]+a[i]*r[j] end
    end
  end
  return out
end
local function around(center,k,p) return add(center,rotate(sub(p,center),k)) end
local function key(a) return table.concat(a,",") end
local re,im={},{}
for i=1,8 do re[i],im[i]=math.cos((i-1)*math.pi/10),math.sin((i-1)*math.pi/10) end
local function coordinates(a,denominator)
  local x,y=0,0
  for i=1,8 do x=x+a[i]*re[i];y=y+a[i]*im[i] end
  return {x/denominator,y/denominator}
end
local labels={
  thick={"a","b","c","d","e","f","e","g","a","b","h","g"},
  thin={"a","f","c","d","e","g","a","b","h","g"},
}
local classes={a=1,g=1,b=2,e=2,c=3,d=3,f=4,h=4}
local forward={a=true,b=true,c=true,f=true}
local partners={a="g",g="a",b="e",e="b",c="d",d="c",f="h",h="f"}
local anchors={thick="2+2-1-1+",thin="1-2+2-1+"}
local function original(k)
  local a=scale(rotate(sub(root(k),root(-k)),-5),D)
  local b=scale(rotate(add(root(k),root(-k)),5),D)
  return a,b,scale(a,-1),scale(b,-1)
end
local function prototypes(values)
  local function delta(i,k)
    return scale(sub(scale(root(k),values[i]),scale(root(k+5),values[i+1])),2)
  end
  local a,b,_,d=original(2)
  local e,f=add(a,delta(1,7)),add(a,delta(3,7))
  local g,h=around(b,-4,f),around(b,-4,e)
  local i,j=add(d,delta(3,5)),add(d,delta(1,5))
  local k,l,m=around(d,-4,j),around(d,-4,i),around(d,-4,h)
  local thick={a,e,f,b,g,h,i,j,d,k,l,m}
  local c
  a,b,c,d=original(1)
  e,f=add(a,delta(1,12)),add(b,delta(3,14))
  g=around(c,-8,f)
  h,i=add(d,delta(1,6)),add(d,delta(1,2))
  j,k=around(a,8,f),around(a,8,e)
  return {thick=thick,thin={a,e,f,c,g,h,d,i,j,k}}
end
local function middle(a,b,amount)
  return add(scale(add(a,b),D),scale(rotate(sub(b,a),5),2*amount))
end
local function shape(proto,kind,values)
  local out={}
  for i,a in ipairs(proto) do
    local b=proto[i%#proto+1]
    local label=labels[kind][i]
    local q=values[4+classes[label]]
    out[#out+1]=coordinates(a,2*D)
    if q~=0 then out[#out+1]=coordinates(middle(a,b,forward[label] and q or -q),4*D*D) end
  end
  return out
end
function M.shapes(values)
  local p=prototypes(values)
  return {shape(p.thick,"thick",values),shape(p.thin,"thin",values)}
end
function M.baseline()
  local out={}
  for _,k in ipairs{2,1} do
    local a={}
    for _,p in ipairs{original(k)} do a[#a+1]=coordinates(p,2*D) end
    out[#out+1]=a
  end
  return out
end
function M.domain()
  return {75,70,204,20,0,0,0,0},{{42,105},{45,104},{170,246},{8,48},
    {-28,28},{-28,28},{-28,28},{-28,28}}
end
local function lifted(k)
  local point=zero()
  for i,v in ipairs(k) do point=add(point,scale(root(4*(i-1)),2*D*v)) end
  return point
end
local function placement(cell,edges,vertices)
  local corners,marks={},{}
  for i,use in ipairs(cell.boundary) do
    local edge=edges[use.edge]
    local from=use.reversed and edge.to or edge.from
    corners[i]=vertices[from].lift
    marks[i]=edge.matching.multiplicity..(edge.matching.from==from and "+" or "-")
  end
  for i,k in ipairs(corners) do
    local tag={}
    for j=0,3 do tag[#tag+1]=marks[(i+j-1)%4+1] end
    if table.concat(tag)==anchors[cell.prototype] then
      local next_lift=corners[i%4+1]
      local direction
      for j,v in ipairs(k) do
        local d=next_lift[j]-v
        if d~=0 then
          assert(not direction and math.abs(d)==1,"escher-p3-source-edge-direction")
          direction=4*(j-1)+(d<0 and 10 or 0)
        end
      end
      assert(direction,"escher-p3-zero-source-edge")
      return lifted(k),direction-(cell.prototype=="thick" and 7 or 6),k
    end
  end
  error("escher-p3-arrow-anchor")
end
local function map(items)
  local out={}
  for _,v in ipairs(items) do out[v.id]=v end
  return out
end
local function sorted(t)
  local out={}
  for k in pairs(t) do out[#out+1]=k end
  table.sort(out,P.byte_less)
  return out
end
local function bounds(points)
  local a,b,c,d=math.huge,math.huge,-math.huge,-math.huge
  for _,p in ipairs(points) do a,b,c,d=math.min(a,p[1]),math.min(b,p[2]),math.max(c,p[1]),math.max(d,p[2]) end
  return {a,b,c,d}
end
local function hits(a,b)
  return a[1]<=b[3] and a[2]<=b[4] and a[3]>=b[1] and a[4]>=b[2]
end
local function winding(polygons,query,scale_cm)
  local policy=G.policy("cm",scale_cm)
  for _,f in ipairs{{.437,.563},{.291,.467},{.739,.317}} do
    local q={query[1]+f[1]*(query[3]-query[1]),query[2]+f[2]*(query[4]-query[2])}
    local inside,boundary=0,false
    for _,poly in ipairs(polygons) do
      if hits(poly.box,{q[1],q[2],q[1],q[2]}) then
        local r=G.region(poly.points,P.array(),policy)
        local classified=G.contains(r,q)
        if classified=="boundary" then boundary=true
        elseif classified=="inside" then inside=inside+1 end
      end
    end
    if not boundary then
      assert(inside==1,"escher-p3-query-winding")
      return q
    end
  end
  error("escher-p3-no-unambiguous-winding-witness")
end
function M.patch(source,values,query,prefix,context)
  local protos=prototypes(values)
  for _,p in ipairs(M.shapes(values)) do Metric.polygon(p) end
  local request=source.extensions.penrose.request
  local origin,step=source.frame.origin,request.step_cm
  local function world(a,d)
    local p=coordinates(a,d)
    return {origin[1]+step*p[1],origin[2]+step*p[2]}
  end
  local tiling=source.structures.tiling
  local vertices,edges=map(tiling.vertices),map(tiling.edges)
  local global,point_map,polygons={},{},{}
  local cells=P.array()
  local function ensure_point(a)
    local k=key(a)
    if not point_map[k] then
      point_map[k]={id=prefix.."/v/"..k,point=world(a,2*D),cyclotomic=a}
    end
    return point_map[k]
  end
  for _,cell in ipairs(tiling.cells) do
    local anchor,rotation,lift=placement(cell,edges,vertices)
    local proto=protos[cell.prototype]
    local points,walk,boundary={},P.array(),P.array()
    for i,p in ipairs(proto) do points[i]=add(anchor,rotate(sub(p,proto[1]),rotation)) end
    local id=prefix.."/c/"..table.concat(cell.address,"/")
    for i,a in ipairs(points) do
      local b=points[i%#points+1]
      local va,vb=ensure_point(a),ensure_point(b)
      local ka,kb=key(a),key(b)
      local reverse=P.byte_less(kb,ka)
      local eid=reverse and kb.."+"..ka or ka.."+"..kb
      local label=labels[cell.prototype][i]
      local amount=values[4+classes[label]]*(forward[label] and 1 or -1)
      local bend=amount~=0 and middle(a,b,amount) or nil
      walk[#walk+1]=va.point
      if bend then walk[#walk+1]=world(bend,4*D*D) end
      local e=global[eid]
      if not e then
        e={id=prefix.."/e/"..eid,from=reverse and vb.id or va.id,to=reverse and va.id or vb.id,
          midpoint=bend,uses={},family=classes[label]}
        global[eid]=e
      else
        local first=e.uses[1]
        assert(#e.uses==1 and first.reverse~=reverse and partners[first.label]==label,
          "escher-p3-fundamental-edge-incidence")
        assert((not bend and not e.midpoint) or (bend and e.midpoint and key(bend)==key(e.midpoint)),
          "escher-p3-coupled-bend-mismatch")
      end
      e.uses[#e.uses+1]={cell=id,label=label,reverse=reverse}
      boundary[i]={edge=e.id,reversed=reverse}
    end
    polygons[#polygons+1]={points=walk,box=bounds(walk)}
    cells[#cells+1]={id=id,prototype=cell.prototype,chirality=1,boundary=boundary,
      source_ref=cell.id,source_anchor=lift,rotation=rotation}
  end
  local out_edges,out_vertices=P.array(),P.array()
  local pairs,outer=0,0
  for _,k in ipairs(sorted(global)) do
    local e=global[k]
    local first,second=table.unpack(e.uses)
    local role=second and "interior" or "patch_boundary"
    local a,b=k:match("^([^+]+)%+([^+]+)$")
    local path={point_map[a].point}
    if e.midpoint then path[2]=world(e.midpoint,4*D*D) end
    path[#path+1]=point_map[b].point
    if second then pairs=pairs+1 else
      outer=outer+1
      assert(not hits(bounds(path),query),"escher-p3-unpaired-side-in-query")
    end
    local owner=second and P.byte_less(second.cell,first.cell) and second.cell or first.cell
    out_edges[#out_edges+1]={id=e.id,from=e.from,to=e.to,owner=owner,role=role,path=path,
      class=e.family,incidence=e.uses,exact_midpoint=e.midpoint}
  end
  for _,k in ipairs(sorted(point_map)) do out_vertices[#out_vertices+1]=point_map[k] end
  if context then context:consume("objects",#cells+#out_edges+#out_vertices) end
  local proof={method=M.VERSION,paired_edges=pairs,outer_edges=outer,query=P.plain(query),
    winding_witness=winding(polygons,query,step),winding=1,coordinate_denominator=2*D,
    midpoint_denominator=4*D*D,source_sha256=H.sha256(P.serialize(source)),
    edge_pairs={{"a","g"},{"b","e"},{"c","d"},{"f","h"}}}
  return {cells=cells,edges=out_edges,vertices=out_vertices},proof
end
return M
