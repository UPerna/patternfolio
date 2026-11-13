-- Bounded centimeter-space fields and straight-segment domain predicates.
local M={VERSION="stroke-field-v1"}
local abs,sqrt,min,max=math.abs,math.sqrt,math.min,math.max
local function finite(v)
  return type(v)=="number" and v==v and abs(v)<1000
end
M.finite=finite

function M.point(p)
  assert(type(p)=="table" and #p==2 and finite(p[1]) and finite(p[2]),"stroke-field-point")
  return {p[1],p[2]}
end

function M.new(bounds,holes,field)
  assert(type(bounds)=="table" and #bounds==4,"stroke-domain-bounds")
  for _,v in ipairs(bounds) do assert(finite(v),"stroke-domain-bounds") end
  assert(bounds[1]<bounds[3] and bounds[2]<bounds[4],"stroke-domain-bounds")
  holes=holes or {}
  assert(type(holes)=="table" and #holes<=16,"stroke-domain-holes")
  local clean={}
  for i,h in ipairs(holes) do
    assert(type(h)=="table" and finite(h.radius) and h.radius>0,"stroke-domain-hole")
    clean[i]={center=M.point(h.center),radius=h.radius}
  end
  assert(type(field)=="table","stroke-field")
  local dir=field.direction
  assert(dir=="uniform" or dir=="vortex" or dir=="radial","stroke-field-direction")
  local origin=M.point(field.origin or {(bounds[1]+bounds[3])/2,(bounds[2]+bounds[4])/2})
  local vector=M.point(field.vector or {1,0})
  assert(dir~="uniform" or vector[1]^2+vector[2]^2>1e-12,"stroke-field-zero-vector")
  local density=field.density or {1,1}
  density=M.point(density)
  assert(min(table.unpack(density))>=0 and max(table.unpack(density))<=1,"stroke-field-density")
  return {bounds={table.unpack(bounds)},holes=clean,direction=dir,origin=origin,vector=vector,density=density}
end

function M.direction(f,p)
  local dx,dy
  if f.direction=="uniform" then dx,dy=table.unpack(f.vector)
  else
    dx,dy=p[1]-f.origin[1],p[2]-f.origin[2]
    if f.direction=="vortex" then dx,dy=-dy,dx end
  end
  local n=sqrt(dx*dx+dy*dy)
  if n<=1e-8 then return nil,"singularity" end
  return {dx/n,dy/n}
end

function M.density(f,p)
  local t=max(0,min(1,(p[1]-f.bounds[1])/(f.bounds[3]-f.bounds[1])))
  return (1-t)*f.density[1]+t*f.density[2]
end

function M.distance2(p,a,b)
  local x,y=b[1]-a[1],b[2]-a[2]
  local d=x*x+y*y
  local t=d>0 and max(0,min(1,((p[1]-a[1])*x+(p[2]-a[2])*y)/d)) or 0
  return (p[1]-a[1]-t*x)^2+(p[2]-a[2]-t*y)^2
end

function M.admissible(f,a,b,padding)
  local l,d,r,t=table.unpack(f.bounds)
  for _,p in ipairs{a,b} do
    if p[1]<l+padding or p[1]>r-padding or p[2]<d+padding or p[2]>t-padding then
      return false,"boundary"
    end
  end
  for _,h in ipairs(f.holes) do
    if M.distance2(h.center,a,b)<=(h.radius+padding)^2 then return false,"hole" end
  end
  return true
end

local function side(a,b,p)
  return (b[1]-a[1])*(p[2]-a[2])-(b[2]-a[2])*(p[1]-a[1])
end

function M.segment_gap2(a,b,c,d)
  local x,y=side(a,b,c),side(a,b,d)
  local z,w=side(c,d,a),side(c,d,b)
  if x*y<0 and z*w<0 then return 0 end
  return min(M.distance2(a,c,d),M.distance2(b,c,d),M.distance2(c,a,b),M.distance2(d,a,b))
end

function M.integrate(f,seed,h,limit,padding,accept)
  assert(finite(h) and h>0 and type(limit)=="number" and limit%1==0 and limit>=0 and limit<=4096,
    "stroke-field-integration-budget")
  local good,reason=M.admissible(f,seed,seed,padding)
  if not good then return {points={seed},stop=reason} end
  local points={seed}
  local sign=h
  local start=M.direction(f,seed)
  if not start then return {points=points,stop="singularity"} end
  if accept and accept.reverse then sign=-h end
  for _=1,limit do
    local p=points[#points]
    local v=M.direction(f,p)
    if not v then return {points=points,stop="singularity"} end
    local mid={p[1]+sign*v[1]/2,p[2]+sign*v[2]/2}
    local w=M.direction(f,mid)
    if not w then return {points=points,stop="singularity"} end
    local q={p[1]+sign*w[1],p[2]+sign*w[2]}
    if f.direction~="uniform" and M.distance2(f.origin,p,q)<=1e-16 then return {points=points,stop="singularity"} end
    good,reason=M.admissible(f,p,q,padding)
    if not good then return {points=points,stop=reason} end
    if accept and accept.segment and not accept.segment(p,q,points) then
      return {points=points,stop="separation"}
    end
    points[#points+1]=q
  end
  return {points=points,stop="step_budget"}
end

return M

