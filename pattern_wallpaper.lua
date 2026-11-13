-- Exact lattice isometries for an explicitly limited set of wallpaper groups.
-- The hexagonal chart uses a 60-degree basis, not the IUCr 120-degree chart.
local P=require("pattern")
local M={VERSION="wallpaper-affine-v1"}
local I={1,0,0,1};local R4={0,-1,1,0};local R6={0,-1,1,1}
local S4={1,0,0,-1};local S6={1,1,0,-1};local half={-1,0,0,-1}
local owned=setmetatable({},{__mode="k"})
local function product(a,b)
  return {a[1]*b[1]+a[2]*b[3],a[1]*b[2]+a[2]*b[4],a[3]*b[1]+a[4]*b[3],a[3]*b[2]+a[4]*b[4]}
end
local function vector(m,p)return{m[1]*p[1]+m[2]*p[2],m[3]*p[1]+m[4]*p[2]}end
local function key(m)return table.concat(m,",")end
local function finite(n)return type(n)=="number"and n==n and math.abs(n)<math.huge end
local function address(t)
  assert(type(t)=="table"and #t==2,"two lattice translation integers required")
  for k,x in pairs(t)do assert((k==1 or k==2)and finite(x)and x%1==0 and math.abs(x)<=1048576,"lattice translation outside exact profile")end
  return {math.tointeger(t[1]),math.tointeger(t[2])}
end
local cases={
  p1={1,I},p2={2,half},p3={3,product(R6,R6),nil,"hexagonal"},
  p4={4,R4,nil,"square"},p4m={4,R4,S4,"square","p4mm"},
  p6={6,R6,nil,"hexagonal"},p6m={6,R6,S6,"hexagonal","p6mm"},
}
function M.names()return{"p1","p2","p3","p4","p4m","p6","p6m"}end
function M.group(name,lattice)
  name=({p4mm="p4m",p6mm="p6m"})[name]or name
  local c=assert(cases[name],"unsupported wallpaper group "..tostring(name))
  assert(lattice=="square"or lattice=="hexagonal","explicit admitted lattice metric required")
  assert(not c[4]or c[4]==lattice,"wallpaper operation does not preserve this lattice metric")
  local ops,map,keys={},{},{};local r=I
  local function add(id,m,det,turn)
    assert(not keys[key(m)],"duplicate group operation")
    ops[#ops+1]={id=id,matrix=m,orientation=det,rotation_degrees=turn};map[id]=ops[#ops];keys[key(m)]=id
  end
  for k=0,c[1]-1 do
    add("r"..k,r,1,360*k/c[1])
    if c[3]then add("m"..k,product(r,c[3]),-1,360*k/c[1])end
    r=product(r,c[2])
  end
  assert(key(r)==key(I),"generator order mismatch")
  local function metric(p)return p[1]^2+p[2]^2+(lattice=="hexagonal"and p[1]*p[2]or 0)end
  for _,a in ipairs(ops)do
    for _,p in ipairs({{1,0},{0,1},{1,1}})do assert(metric(vector(a.matrix,p))==metric(p),"group changes exact Gram metric")end
    assert(a.matrix[1]*a.matrix[4]-a.matrix[2]*a.matrix[3]==a.orientation,"wrong group orientation")
    for _,b in ipairs(ops)do assert(keys[key(product(a.matrix,b.matrix))],"group lacks closure")end
  end
  local descriptor=P.snapshot({id=name,international_symbol=c[5]or name,lattice=lattice,operations=ops,
    translations="all integer pairs in the admitted lattice chart",profile=M.VERSION,
    translation_domain={{0,0},{1,0},{1,1},{0,1}},
    asymmetric_unit=name=="p4m"and{{0,0},{0.5,0.5},{0,0.5}}or name=="p6m"and{{0,0},{0.5,0},{1/3,1/3}}or nil})
  owned[descriptor]={map=map,keys=keys};return descriptor
end
local function operation(group,id)
  local data=assert(owned[group],"validated wallpaper descriptor required")
  return assert(data.map[id],"unknown wallpaper operation "..tostring(id)),data
end
function M.element(group,id,translation)
  operation(group,id);return P.snapshot({operation=id,translation=address(translation or{0,0})})
end
function M.apply(group,element,point)
  local o=operation(group,element.operation);local t=address(element.translation)
  assert(type(point)=="table"and #point==2 and finite(point[1])and finite(point[2])and math.abs(point[1])<=1048576 and math.abs(point[2])<=1048576,"lattice point outside bounded profile")
  local p=vector(o.matrix,point);return {p[1]+t[1],p[2]+t[2]},o.orientation
end
function M.compose(group,left,right)
  local a,data=operation(group,left.operation);local b=operation(group,right.operation)
  local l,r=address(left.translation),address(right.translation);local t=vector(a.matrix,r)
  return M.element(group,assert(data.keys[key(product(a.matrix,b.matrix))]),{t[1]+l[1],t[2]+l[2]})
end
function M.inverse(group,e)
  local a,data=operation(group,e.operation);local m=a.matrix
  local inv={m[4]*a.orientation,-m[2]*a.orientation,-m[3]*a.orientation,m[1]*a.orientation}
  local t=vector(inv,address(e.translation))
  return M.element(group,assert(data.keys[key(inv)]),{-t[1],-t[2]})
end
return M
