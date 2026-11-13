local M={VERSION="image-guided-maze-charts-v1"}
local min,max,abs,sqrt,pi=math.min,math.max,math.abs,math.sqrt,math.pi

function M.light(image,u,v)
  if image=="ramp" then return max(0,min(1,u)) end
  if image=="radial" then return max(0,min(1,2*sqrt((u-.5)^2+(v-.5)^2))) end
  if image=="ribbon" then
    return abs(v-(.5+.19*math.sin(2*pi*u)))<.18 and .18 or .78
  end
  return .55
end

function M.tone(g,wmin,pmin,smax)
  local level=pmin/smax+(1-(pmin+wmin)/smax)*g
  if level<=pmin/(pmin+wmin) then
    return pmin/level,pmin*(1-level)/level,level
  end
  return wmin/(1-level),wmin,level
end

local function chart(bounds,q)
  local l,b,r,t=table.unpack(bounds)
  local function project(u,v)
    local k=q.perspective
    local z=1+k*v
    local x=(u-.5)/z+.5
    local y=(1+k)*v/z
    return {l+(r-l)*x,b+(t-b)*y}
  end
  return project
end

local function partition(n,q,axis)
  local weights={}
  local sum=0
  for i=1,n do
    local x=(i-.5)/n
    local g=axis=="x" and M.light(q.image,x,.5) or M.light(q.image,.5,x)
    local step=M.tone(g,q.min_wall,q.min_passage,q.max_spacing)
    weights[i]=step
    sum=sum+step
  end
  local p={0}
  for i,v in ipairs(weights) do p[i+1]=p[i]+v/sum end
  p[#p]=1
  return p
end

local function edge_key(i,j)
  return "grid/"..i.."/"..j
end

local function grid(q,rng)
  local points,cells={},{}
  local map=chart(q.bounds,q)
  local xs,ys=partition(q.cols,q,"x"),partition(q.rows,q,"y")
  if q.profile=="random" or q.profile=="holed" then
    for i=0,q.cols do xs[i+1]=i/q.cols end
    for j=0,q.rows do ys[j+1]=j/q.rows end
  end
  local raw={}
  for j,v in ipairs(ys) do
    for i,u in ipairs(xs) do raw[edge_key(i,j)]={u,v} end
  end
  local relaxations=0
  if q.profile=="random" then
    for j=2,q.rows do
      for i=2,q.cols do
        local a=raw[edge_key(i,j)]
        a[1]=a[1]+(rng.u()-.5)*.31/q.cols
        a[2]=a[2]+(rng.u()-.5)*.31/q.rows
      end
    end
    -- Bounded spring relaxation with a fixed boundary. Small initial
    -- displacement and convex mixing keep the two line families ordered.
    for _=1,q.relax do
      local next_points={}
      for j=1,q.rows+1 do
        for i=1,q.cols+1 do
          local id=edge_key(i,j)
          local p=raw[id]
          if i>1 and i<=q.cols and j>1 and j<=q.rows then
            local x,y=0,0
            for _,k in ipairs{edge_key(i-1,j),edge_key(i+1,j),edge_key(i,j-1),edge_key(i,j+1)} do
              x,y=x+raw[k][1],y+raw[k][2]
            end
            p={.91*p[1]+.0225*x,.91*p[2]+.0225*y}
          end
          next_points[id]=p
        end
      end
      raw=next_points
      relaxations=relaxations+1
    end
  end
  for id,p in pairs(raw) do points[id]={point=map(p[1],p[2]),uv=p} end
  local removed={}
  for j=1,q.rows do
    for i=1,q.cols do
      local u,v=(xs[i]+xs[i+1])/2,(ys[j]+ys[j+1])/2
      local absent=false
      if q.profile=="holed" then
        for _,h in ipairs(q.holes) do
          if (u-h[1])^2+(v-h[2])^2<h[3]^2 then absent=true;break end
        end
        if q.notch and i<=2 and j>=q.rows-1 then absent=true end
      end
      local id="grid/cell/"..i.."/"..j
      if absent then removed[#removed+1]=id
      else
        cells[#cells+1]={id=id,vertices={edge_key(i,j),edge_key(i+1,j),edge_key(i+1,j+1),edge_key(i,j+1)},
          center=map(u,v),slot={i,j},light=M.light(q.image,u,v)}
      end
    end
  end
  return points,cells,{removed=removed,relaxations=relaxations,profile=q.profile,axes={xs,ys}}
end

local function polar(q)
  local points,cells={},{}
  local map=chart(q.bounds,q)
  local n,k=q.cols,q.rows
  local rings={0}
  local sum=0
  for i=1,k do
    local g=M.light(q.image,.5+.45*(i-.5)/k,.5)
    local step=M.tone(g,q.min_wall,q.min_passage,q.max_spacing)
    sum=sum+step
    rings[i+1]=sum
  end
  for i=2,#rings do rings[i]=.48*rings[i]/sum end
  local function vertex(r,i) return "ring/"..r.."/"..(i%n) end
  local function uv(r,i)
    local theta=2*pi*i/n
    return .5+r*math.cos(theta),.5+r*math.sin(theta)
  end
  points.center={point=map(.5,.5),uv={.5,.5}}
  for j=1,k do
    for i=0,n-1 do
      local u,v=uv(rings[j+1],i)
      points[vertex(j,i)]={point=map(u,v),uv={u,v}}
    end
  end
  for j=1,k do
    for i=0,n-1 do
      local u,v=uv((rings[j]+rings[j+1])/2,i+.5)
      local ids
      if j==1 then ids={"center",vertex(j,i),vertex(j,i+1)}
      else ids={vertex(j-1,i),vertex(j,i),vertex(j,i+1),vertex(j-1,i+1)} end
      cells[#cells+1]={id="polar/cell/"..j.."/"..i,vertices=ids,center=map(u,v),slot={j,i},light=M.light(q.image,u,v)}
    end
  end
  return points,cells,{profile=q.profile,radii=rings,angular_sectors=n}
end

function M.build(q,rng)
  if q.profile=="spiral" or q.profile=="vortex" then return polar(q) end
  return grid(q,rng)
end

return M
