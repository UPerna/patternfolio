local M={VERSION="hausner-l1-cpu-v1"}
local abs,min,max,sqrt=math.abs,math.min,math.max,math.sqrt

local function cross(a,b,x,y)
  return (b[1]-a[1])*(y-a[2])-(b[2]-a[2])*(x-a[1])
end

local function inside(panel,x,y)
  for i,a in ipairs(panel) do
    if cross(a,panel[i%#panel+1],x,y)<-1e-12 then return false end
  end
  return true
end
M.inside=inside

local function field(features,x,y)
  local best,ux,uy=math.huge,1,0
  for _,line in ipairs(features) do
    for j=1,#line-1 do
      local a,b=line[j],line[j+1]
      local dx,dy=b[1]-a[1],b[2]-a[2]
      local n=dx*dx+dy*dy
      local t=max(0,min(1,((x-a[1])*dx+(y-a[2])*dy)/n))
      local d=(x-a[1]-t*dx)^2+(y-a[2]-t*dy)^2
      if d<best-1e-12 then best,ux,uy=d,dx/sqrt(n),dy/sqrt(n) end
    end
  end
  return ux,uy,sqrt(best)
end
M.field=field

local function oriented(q,x,y)
  local ux,uy,d=field(q.features,x,y)
  local f=q.guided and max(0,1-d/q.influence) or 0
  local size=q.size*(1-q.size_variation*f)
  local aspect=1+(q.aspect-1)*f
  if not q.guided then ux,uy=1,0 end
  return {x=x,y=y,ux=ux,uy=uy,half_u=size*sqrt(aspect)/2,half_v=size/sqrt(aspect)/2}
end

local function samples(q)
  local out={}
  local l,b,r,t=table.unpack(q.bounds)
  local nx,ny=math.ceil((r-l)/q.sample),math.ceil((t-b)/q.sample)
  assert(nx*ny<=12000,"mosaic-sampling-horizon")
  for j=1,ny do
    for i=1,nx do
      local x,y=l+(i-.5)*(r-l)/nx,b+(j-.5)*(t-b)/ny
      if inside(q.panel,x,y) then
        local _,_,d=field(q.features,x,y)
        out[#out+1]={x,y,d<q.exclusion}
      end
    end
  end
  assert(#out>0,"mosaic-empty-sampling-panel")
  return out
end

local function diagram(grid,sites,strip)
  local accum,energy,used={},0,0
  for i=1,#sites do accum[i]={0,0,0} end
  for _,p in ipairs(grid) do
    if not strip or not p[3] then
      local best,winner=math.huge
      for i,s in ipairs(sites) do
        local dx,dy=p[1]-s.x,p[2]-s.y
        local distance=abs(s.ux*dx+s.uy*dy)/s.half_u+abs(s.ux*dy-s.uy*dx)/s.half_v
        if distance<best-1e-12 then best,winner=distance,i end
      end
      local a=accum[winner]
      a[1],a[2],a[3]=a[1]+p[1],a[2]+p[2],a[3]+1
      energy,used=energy+best,used+1
    end
  end
  return accum,used>0 and energy/used or 0,used
end

local function round(v)
  return math.floor(v*1e10+.5)/1e10
end

function M.solve(q,rng,step)
  local grid=samples(q)
  assert(q.count<=#grid,"mosaic-more-sites-than-samples")
  assert(#grid*q.count*(q.iterations+1)<=24000000,"mosaic-evaluation-horizon")
  local indices={}
  for i=1,#grid do indices[i]=i end
  local centers={}
  for i=1,q.count do
    local j=rng.int(i,#grid)
    indices[i],indices[j]=indices[j],indices[i]
    local p=grid[indices[i]]
    centers[i]={round(p[1]),round(p[2])}
  end
  local initial=centers
  local history={}
  local status="iteration_budget"
  for i=1,q.iterations do
    local strip=q.guided and q.exclusion>0 and i<=q.avoid_steps
    local sites={}
    for j,p in ipairs(centers) do sites[j]=oriented(q,p[1],p[2]) end
    if step then step(#grid*q.count) end
    local accum,energy,used=diagram(grid,sites,strip)
    local moved,empty,next_centers=0,0,{}
    for j,a in ipairs(accum) do
      local x,y=table.unpack(centers[j])
      local next_point=centers[j]
      if a[3]>0 then
        local xx,yy=round(a[1]/a[3]),round(a[2]/a[3])
        moved=max(moved,sqrt((x-xx)^2+(y-yy)^2))
        next_point={xx,yy}
      else empty=empty+1 end
      next_centers[j]=next_point
    end
    history[i]={phase=strip and "feature-exclusion" or "full",energy=energy,samples=used,
      max_motion=moved,empty_regions=empty}
    centers=next_centers
    if used==0 then status="no_active_samples";break end
    if not strip and moved<=q.tolerance and empty==0 then status="stationary";break end
  end
  local sites={}
  for i,p in ipairs(centers) do sites[i]=oriented(q,p[1],p[2]) end
  if step then step(#grid*q.count) end
  local _,final_energy,used=diagram(grid,sites,false)
  return {initial=initial,centers=centers,history=history,status=status,
    final_energy=final_energy,samples=used}
end

local function corners(s,scale)
  local a,b=s.half_u*scale,s.half_v*scale
  local out={}
  for i,k in ipairs{{-1,-1},{1,-1},{1,1},{-1,1}} do
    out[i]={s.x+k[1]*a*s.ux-k[2]*b*s.uy,s.y+k[1]*a*s.uy+k[2]*b*s.ux}
  end
  return out
end

local function overlaps(a,b,gap)
  for _,axis in ipairs{a,b} do
    for j=1,2 do
      local x,y=axis.ux,axis.uy
      if j==2 then x,y=-y,x end
      local function radius(s)
        return (s.half_u*abs(s.ux*x+s.uy*y)+s.half_v*abs(s.ux*y-s.uy*x))*s.scale
      end
      if abs((a.x-b.x)*x+(a.y-b.y)*y)>=radius(a)+radius(b)+gap then return false end
    end
  end
  return true
end

function M.pack(q,centers)
  local sites,tiles,rejected={},{},{}
  local area=0
  for i,p in ipairs(centers) do
    local s=oriented(q,p[1],p[2])
    local function fits(scale)
      for _,v in ipairs(corners(s,scale)) do
        if not inside(q.panel,v[1],v[2]) then return false end
      end
      s.scale=scale
      for _,other in ipairs(sites) do
        if overlaps(s,other,q.grout) then return false end
      end
      return true
    end
    if fits(q.min_scale) then
      local lo,hi=q.min_scale,1
      if fits(1) then lo=1
      else
        for _=1,22 do
          local mid=(lo+hi)/2
          if fits(mid) then lo=mid else hi=mid end
        end
      end
      s.scale=lo
      sites[#sites+1]=s
      tiles[#tiles+1]={site=i,center=p,axis={s.ux,s.uy},corners=corners(s,lo),scale=lo}
      area=area+4*s.half_u*s.half_v*lo*lo
    else rejected[#rejected+1]=i end
  end
  return tiles,rejected,area
end

return M


