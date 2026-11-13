-- Periodic polygon templates in exact lattice coordinates. A point is
-- {(u0+u1 sqrt(D))/6, (v0+v1 sqrt(D))/6}, stored as four integers.
local P=require("pattern")
local M={VERSION="periodic-templates-v1",DENOMINATOR=6}
local Z={0,0,0,0};local I={1,0,0,1};local R4={0,-1,1,0};local R6={0,-1,1,1};local S={1,1,0,-1}
local function q(u,v)return {u,0,v,0}end
local function add(a,b)return{a[1]+b[1],a[2]+b[2],a[3]+b[3],a[4]+b[4]}end
local function sub(a,b)return{a[1]-b[1],a[2]-b[2],a[3]-b[3],a[4]-b[4]}end
local function linear(m,p)
  return{m[1]*p[1]+m[2]*p[3],m[1]*p[2]+m[2]*p[4],m[3]*p[1]+m[4]*p[3],m[3]*p[2]+m[4]*p[4]}
end
local function shift(p,i,j)return{p[1]+6*i,p[2],p[3]+6*j,p[4]}end
local function key(p)return table.concat(p,"/")end
local function same(a,b)return a[1]==b[1]and a[2]==b[2]and a[3]==b[3]and a[4]==b[4]end
local function value(p,d)local r=math.sqrt(d);return {(p[1]+r*p[2])/6,(p[3]+r*p[4])/6}end
local function sign(a,b,d)
  if b==0 then return a>0 and 1 or a<0 and -1 or 0 end
  if a==0 then return b>0 and 1 or -1 end
  if a>0 and b>0 then return 1 elseif a<0 and b<0 then return -1 end
  local x=a*a-d*b*b
  assert(x~=0,"unexpected rational radical cancellation")
  return (x>0)==(a>0)and 1 or -1
end
local function cross(a,b,d)
  return a[1]*b[3]+d*a[2]*b[4]-a[3]*b[1]-d*a[4]*b[2],
         a[1]*b[4]+a[2]*b[3]-a[3]*b[2]-a[4]*b[1]
end
local function orient(a,b,c,d)local x,y=cross(sub(b,a),sub(c,a),d);return sign(x,y,d)end
local function metric(a,b,d,hex)
  local x=2*(a[1]*b[1]+d*a[2]*b[2]+a[3]*b[3]+d*a[4]*b[4])
  local y=2*(a[1]*b[2]+a[2]*b[1]+a[3]*b[4]+a[4]*b[3])
  if hex then
    x=x+a[1]*b[3]+d*a[2]*b[4]+a[3]*b[1]+d*a[4]*b[2]
    y=y+a[1]*b[4]+a[2]*b[3]+a[3]*b[2]+a[4]*b[1]
  end
  return x,y -- twice the dot product, denominator 36
end
local function order(points,c,d)
  table.sort(points,function(p,q_)
    local a,b=sub(p,c),sub(q_,c)
    local function half(x)local sy=sign(x[3],x[4],d);return (sy>0 or sy==0 and sign(x[1],x[2],d)>=0)and 0 or 1 end
    local ha,hb=half(a),half(b);if ha~=hb then return ha<hb end
    local x,y=cross(a,b,d);return sign(x,y,d)>0
  end)
  return points
end
local function orbit(seed,center,rotation,count,mirror,d)
  local out,seen={},{};local a=sub(seed,center);local b=mirror and linear(mirror,a)
  local function insert(v)local p=add(center,v);local k=key(p);if not seen[k]then seen[k]=true;out[#out+1]=p end end
  for _=1,count do insert(a);a=linear(rotation,a);if b then insert(b);b=linear(rotation,b)end end
  return order(out,center,d)
end
local function face(id,prototype,center,points,rotation)
  return {id=id,prototype=prototype,center=center,vertices=points,rotation_degrees=rotation or 0}
end
local function transformed(f,id,rotation,m,translation)
  local points={};for i,p in ipairs(f.vertices)do points[i]=add(linear(m,p),translation)end
  return face(id,f.prototype,add(linear(m,f.center),translation),points,rotation)
end
local cases={}
cases.square=function()
  return "square",2,{face("s","square",q(3,3),{q(0,0),q(6,0),q(6,6),q(0,6)})}
end
cases.triangular=function()
  local a=face("up","triangle",q(2,2),{q(0,0),q(6,0),q(0,6)})
  return "hexagonal",3,{a,transformed(a,"down",180,{-1,0,0,-1},q(6,6))}
end
cases.hexagonal=function()
  return "hexagonal",3,{face("h","hexagon",Z,orbit(q(2,2),Z,R6,6,nil,3))}
end
cases["4.8.8"]=function()
  -- Truncate the vertices of a unit square by 1-sqrt(2)/2 of its side.
  local cut={-3,3,-3,0} -- (sqrt(2)/2-1/2, -1/2)
  local center=q(3,3)
  local oct=face("oct","octagon",Z,orbit(cut,Z,R4,4,{1,0,0,-1},2))
  local small=face("gap","square",center,orbit({3,0,-3,3},center,R4,4,nil,2))
  return "square",2,{oct,small}
end
cases["4.6.12"]=function()
  -- The incenter of the 30/90/60 degree p6m chamber:
  -- A=(0,0), B=(1/2,0), C=(1/3,1/3) in the 60-degree chart.
  local seed={2,0,-1,1};local B,C=q(3,0),q(2,2)
  local d=face("d","dodecagon",Z,orbit(seed,Z,R6,6,S,3))
  local s=face("s0","square",B,orbit(seed,B,{-1,0,0,-1},2,S,3))
  local h=face("h0","hexagon",C,orbit(seed,C,{-1,-1,1,0},3,{0,1,1,0},3))
  return "hexagonal",3,{d,s,transformed(s,"s1",60,R6,Z),
    transformed(s,"s2",120,{-1,-1,1,0},q(6,0)),
    h,transformed(h,"h1",180,{-1,0,0,-1},q(6,6))}
end
local function edge_signature(a,b)
  local ai,aj=a[1]//6,a[3]//6;local bi,bj=b[1]//6,b[3]//6
  local ab=key(shift(a,-ai,-aj))..":"..key(shift(b,-ai,-aj))
  local ba=key(shift(b,-bi,-bj))..":"..key(shift(a,-bi,-bj))
  assert(ab~=ba,"degenerate quotient edge")
  if ab<ba then return ab,{ai,aj},false end
  return ba,{bi,bj},true
end
local function separates(a,b,dx,dy,d)
  for i,p in ipairs(a)do
    local q_=a[i%#a+1];local outside=true
    for _,r in ipairs(b)do if orient(p,q_,shift(r,dx,dy),d)>0 then outside=false;break end end
    if outside then return true end
  end
  return false
end
local cache={}
function M.names()return {"square","triangular","hexagonal","4.8.8","4.6.12"}end
function M.get(name)
  if cache[name]then return cache[name]end
  local lattice,d,faces=assert(cases[name],"unsupported periodic tiling "..tostring(name))()
  local areas,edges,seen={}, {}, {};local totalA,totalB=0,0;local lowU,highU,lowV,highV
  local metricA,metricB
  for _,f in ipairs(faces)do
    assert(not seen[f.id],"duplicate prototype address");seen[f.id]=f;f.neighbors={}
    local ar,br=0,0;local dotA,dotB
    for i,p in ipairs(f.vertices)do
      local b=f.vertices[i%#f.vertices+1];local next_=f.vertices[(i+1)%#f.vertices+1]
      assert(orient(p,b,next_,d)>0 and orient(p,b,f.center,d)>0,"prototype not strictly convex CCW about its center")
      local x,y=cross(p,b,d);ar,br=ar+x,br+y
      local e=sub(b,p);x,y=metric(e,e,d,lattice=="hexagonal")
      metricA,metricB=metricA or x,metricB or y
      assert(x==metricA and y==metricB,"different exact edge lengths in periodic complex")
      x,y=metric(e,sub(next_,b),d,lattice=="hexagonal");dotA,dotB=dotA or x,dotB or y
      assert(x==dotA and y==dotB,"prototype is not equiangular")
      local sig,anchor,reverse=edge_signature(p,b)
      edges[sig]=edges[sig]or{};edges[sig][#edges[sig]+1]={face=f,index=i,anchor=anchor,reverse=reverse}
      if not lowU or sign(p[1]-lowU[1],p[2]-lowU[2],d)<0 then lowU=p end
      if not highU or sign(p[1]-highU[1],p[2]-highU[2],d)>0 then highU=p end
      if not lowV or sign(p[3]-lowV[3],p[4]-lowV[4],d)<0 then lowV=p end
      if not highV or sign(p[3]-highV[3],p[4]-highV[4],d)>0 then highV=p end
    end
    assert(sign(ar,br,d)>0,"nonpositive prototype area")
    areas[f.id]={ar,br};totalA,totalB=totalA+ar,totalB+br
  end
  assert(totalA==72 and totalB==0,"prototype areas do not cover a unit lattice domain")
  assert(sign(highU[1]-lowU[1]-12,highU[2]-lowU[2],d)<=0 and sign(highV[3]-lowV[3]-12,highV[4]-lowV[4],d)<=0,
    "prototype support exceeds neighbor proof range")
  local classes=0
  for sig,items in pairs(edges)do
    classes=classes+1;assert(#items==2 and items[1].reverse~=items[2].reverse,"unpaired periodic edge: "..sig)
    for i,r in ipairs(items)do
      local other=items[3-i];local di,dj=r.anchor[1]-other.anchor[1],r.anchor[2]-other.anchor[2]
      local a,b=r.face.vertices[r.index],r.face.vertices[r.index%#r.face.vertices+1]
      local c,e=other.face.vertices[other.index],other.face.vertices[other.index%#other.face.vertices+1]
      assert(same(a,shift(e,di,dj))and same(b,shift(c,di,dj)),"incorrect periodic edge correspondence")
      r.face.neighbors[r.index]={template=other.face.id,edge=other.index,offset={di,dj},class=sig}
    end
  end
  local pairs_checked=0
  for i,a in ipairs(faces)do for j,b in ipairs(faces)do for dx=-2,2 do for dy=-2,2 do
    if i~=j or dx~=0 or dy~=0 then
      pairs_checked=pairs_checked+1
      assert(separates(a.vertices,b.vertices,dx,dy,d)or separates(b.vertices,a.vertices,-dx,-dy,d),
        "positive interior overlap: "..a.id.."/"..b.id.."/"..dx.."/"..dy)
    end
  end end end end
  local descriptor=P.snapshot({id=name,profile=M.VERSION,lattice=lattice,radicand=d,denominator=6,faces=faces,
    support={value(lowU,d)[1],value(lowV,d)[2],value(highU,d)[1],value(highV,d)[2]},
    certificate={doubled_lattice_areas=areas,doubled_domain_area={totalA,totalB},twice_squared_edge_length={metricA,metricB},product_denominator=36,
      paired_edge_classes=classes,relative_shift_extent=2,convex_pairs_checked=pairs_checked}})
  cache[name]=descriptor;return descriptor
end
M.point_value=value
M.shift=shift
M.key=key
return M
