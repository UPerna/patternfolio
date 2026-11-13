-- Bounded IH41 parallelogram chart. The periodic displacement map
-- F(x,y)=(x+g(y),y+f(x)) preserves the partition when Lip(f)*Lip(g)<1.
local P,R=require("pattern"),require("pattern_exact")
local M={VERSION="ih41-translation-chart-v1"}
local D=512
local half=R.new(1,2)
local function knot(i) return R.new(i,4) end
local function number(q) return q[1]/q[2] end
local function value_at(values,t)
  if t[1]==t[2] then return values[5] end
  local k=(4*t[1])//t[2]
  return R.add(values[k+1],R.mul(R.sub(values[k+2],values[k+1]),R.sub(R.mul(R.new(4),t),R.new(k))))
end
local function controls(values,start)
  return {R.new(0),R.new(values[start],D),R.new(values[start+1],D),R.new(values[start+2],D),R.new(0)}
end
local function slope(values)
  local maximum=0
  for i=1,4 do maximum=math.max(maximum,4*math.abs(number(R.sub(values[i+1],values[i])))) end
  return maximum
end
local function chart(values,split)
  local f,g=controls(values,1),controls(values,4)
  local a,b=slope(f),slope(g)
  if a*b>=.92 then return nil end
  local horizontal,vertical={},{}
  for i=0,4 do
    horizontal[i+1]={knot(i),f[i+1]}
    vertical[i+1]={g[i+1],knot(i)}
  end
  local paths={vertical=vertical}
  if split then
    paths.west={horizontal[1],horizontal[2],horizontal[3]}
    paths.east={horizontal[3],horizontal[4],horizontal[5]}
    local seam={}
    local h=controls(values,7)
    local function add(y)
      local x=R.add(half,value_at(h,y))
      assert(R.compare(x,knot(1))>0 and R.compare(x,knot(3))<0,"escher-split-outside-chart")
      seam[#seam+1]={R.add(x,value_at(g,y)),R.add(y,value_at(f,x))}
    end
    for i=0,3 do
      add(knot(i))
      local u,v=h[i+1],h[i+2]
      if u[1]*v[1]<0 then
        add(R.add(knot(i),R.mul(knot(1),R.div(u,R.sub(u,v)))))
      end
    end
    add(knot(4))
    paths.split=seam
  else
    paths.horizontal=horizontal
  end
  return paths,{f_lipschitz=a,g_lipschitz=b,product=a*b}
end
local function use(name,x,y,reversed) return {family=name,x=x,y=y,reversed=reversed or false} end
local mono={{prototype="mono",edges={use("horizontal",0,0),use("vertical",1,0),
  use("horizontal",0,1,true),use("vertical",0,0,true)}}}
local split_faces={
  {prototype="west",edges={use("west",0,0),use("split",0,0),use("west",0,1,true),use("vertical",0,0,true)}},
  {prototype="east",edges={use("east",0,0),use("vertical",1,0),use("east",0,1,true),use("split",0,0,true)}},
}
local function world(p,request)
  local x,y=number(p[1]),number(p[2])
  return {request.frame.origin[1]+request.step_cm*(x+request.shear*y),
    request.frame.origin[2]+request.step_cm*request.aspect*y}
end
local function translate(p,x,y)
  return {R.add(p[1],R.new(x)),R.add(p[2],R.new(y))}
end
local function face_points(face,paths,request)
  local out={}
  for _,e in ipairs(face.edges) do
    local line=paths[e.family]
    for i=1,#line-1 do
      local p=line[e.reversed and #line-i+1 or i]
      out[#out+1]=world(translate(p,e.x,e.y),request)
    end
  end
  return out
end
function M.shapes(values,request)
  local split=request.profile=="split"
  local paths=chart(values,split)
  if not paths then return nil end
  local out={}
  local basis={frame={origin={0,0}},step_cm=1,shear=request.shear,aspect=request.aspect}
  for i,face in ipairs(split and split_faces or mono) do out[i]=face_points(face,paths,basis) end
  return out
end
function M.domain(split)
  local values,bounds={},{}
  for i=1,(split and 9 or 6) do
    values[i]=0
    local max=i>6 and 96 or 82
    bounds[i]={-max,max}
  end
  return values,bounds
end
local function key(p)
  return p[1][1]..":"..p[1][2]..","..p[2][1]..":"..p[2][2]
end
local function sorted(map)
  local out={}
  for k in pairs(map) do out[#out+1]=k end
  table.sort(out,P.byte_less)
  return out
end
local function index_limits(request)
  local q,o=request.query,request.frame.origin
  local lo,hi={math.huge,math.huge},{-math.huge,-math.huge}
  for _,p in ipairs{{q[1],q[2]},{q[3],q[2]},{q[3],q[4]},{q[1],q[4]}} do
    local y=(p[2]-o[2])/(request.step_cm*request.aspect)
    local x=(p[1]-o[1])/request.step_cm-request.shear*y
    assert(math.abs(x)<=64 and math.abs(y)<=64,"escher-periodic-query-horizon")
    lo[1],lo[2]=math.min(lo[1],x),math.min(lo[2],y)
    hi[1],hi[2]=math.max(hi[1],x),math.max(hi[2],y)
  end
  for i=1,2 do lo[i],hi[i]=math.floor(lo[i])-1,math.ceil(hi[i])+1 end
  assert((hi[1]-lo[1]+1)*(hi[2]-lo[2]+1)<=300,"escher-periodic-cell-budget")
  return lo,hi
end
function M.patch(request,values,prefix,context)
  local split=request.profile=="split"
  local paths,proof=chart(values,split)
  assert(paths,"escher-periodic-noncontractive")
  local lo,hi=index_limits(request)
  local vertices,edges,cells=P.array(),P.array(),P.array()
  local by_point,by_edge={},{}
  local function vertex(p)
    local k=key(p)
    if not by_point[k] then
      by_point[k]={id=prefix.."/v/"..k,point=world(p,request),rational_chart=p}
    end
    return by_point[k].id
  end
  for j=lo[2],hi[2] do for i=lo[1],hi[1] do
    for _,face in ipairs(split and split_faces or mono) do
      local id=prefix.."/c/"..i.."/"..j.."/"..face.prototype
      local boundary=P.array()
      for n,use in ipairs(face.edges) do
        local x,y=i+use.x,j+use.y
        local k=use.family.."/"..x.."/"..y
        local e=by_edge[k]
        if not e then
          local geometry,points={},{}
          for m,p in ipairs(paths[use.family]) do
            geometry[m]=translate(p,x,y)
            points[m]=world(geometry[m],request)
          end
          e={id=prefix.."/e/"..k,from=vertex(geometry[1]),to=vertex(geometry[#geometry]),
            path=points,rational_chart=geometry,incidence=P.array(),family=use.family}
          by_edge[k]=e
        end
        local first=e.incidence[1]
        assert(#e.incidence<2 and (not first or first.reversed~=use.reversed),"escher-periodic-incidence")
        e.incidence[#e.incidence+1]={cell=id,reversed=use.reversed}
        boundary[n]={edge=e.id,reversed=use.reversed}
      end
      cells[#cells+1]={id=id,prototype=face.prototype,chirality=1,boundary=boundary,source_slot={i,j}}
    end
  end end
  local paired=0
  for _,k in ipairs(sorted(by_edge)) do
    local e=by_edge[k]
    local first,second=table.unpack(e.incidence)
    e.owner=second and P.byte_less(second.cell,first.cell) and second.cell or first.cell
    e.role=second and "interior" or "patch_boundary"
    if second then paired=paired+1 end
    edges[#edges+1]=e
  end
  for _,k in ipairs(sorted(by_point)) do vertices[#vertices+1]=by_point[k] end
  if context then context:consume("objects",#cells+#edges+#vertices) end
  proof.method=M.VERSION
  proof.isohedral="IH41"
  proof.split=split
  proof.paired_edges=paired
  proof.rectangular_source_slots={lo,hi}
  proof.source_basis={{request.step_cm,0},{request.step_cm*request.shear,request.step_cm*request.aspect}}
  proof.families=split and {{"west","east"},"vertical","split"} or {"horizontal","vertical"}
  return {cells=cells,edges=edges,vertices=vertices},proof
end
return M
