local M={VERSION="micrography-signed-boundary-rosy-v1"}
local abs,min,max,sqrt,pi=math.abs,math.min,math.max,math.sqrt,math.pi

local function cross(a,b)
  return a[1]*b[2]-a[2]*b[1]
end
local function sub(a,b) return {a[1]-b[1],a[2]-b[2]} end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2] end
local function length(a) return sqrt(dot(a,a)) end
local function unit(a)
  local n=length(a)
  return {a[1]/n,a[2]/n}
end
local function rotate(v,a)
  local c,s=math.cos(a),math.sin(a)
  return {c*v[1]-s*v[2],s*v[1]+c*v[2]}
end
local function mix(a,b,t)
  return {(1-t)*a[1]+t*b[1],(1-t)*a[2]+t*b[2]}
end

function M.contained(panel,p,padding)
  for i,a in ipairs(panel) do
    local v=sub(panel[i%4+1],a)
    if cross(v,sub(p,a))<padding*length(v)-1e-12 then return false end
  end
  return true
end

local function alignment(a,b)
  local angle=math.acos(min(1,abs(dot(a,b))))
  local x=1-4*angle/pi
  local e=math.exp(2*x)
  return (e-1)/(e+1)
end

local function distance_factor(cm,size,sigma)
  local d=max(cm/size-5,0)
  return math.exp(-(d/sigma)^2)
end

local function attraction(panel,sample,size)
  local inward={-sample.tangent[2],sample.tangent[1]}
  local hits={}
  for _,angle in ipairs{-.28,-.14,0,.14,.28} do
    local ray=rotate(inward,angle)
    local best,opposite=math.huge
    for i,a in ipairs(panel) do
      local b=panel[i%4+1]
      local side=sub(b,a)
      local denom=cross(ray,side)
      if abs(denom)>1e-12 then
        local rel=sub(a,sample.point)
        local t,u=cross(rel,side)/denom,cross(rel,ray)/denom
        if t>1e-10 and t<best and u>=-1e-12 and u<=1+1e-12 then
          best,opposite=t,unit(side)
        end
      end
    end
    if opposite then
      hits[#hits+1]={distance=best,alignment=alignment(sample.tangent,opposite)}
    end
  end
  assert(#hits>=3,"micrography-opposite-ray-horizon")
  table.sort(hits,function(a,b) return a.distance<b.distance end)
  local d,a=0,0
  for i=2,#hits-1 do d,a=d+hits[i].distance,a+hits[i].alignment end
  local n=#hits-2
  return max(0,a/n)*distance_factor(d/n,size,20),hits
end

local function boundary(panel,size,n,omega,fixed)
  local samples,edges={},{}
  local sum_weights,sum_attract=0,0
  local function node(i,j) return (j-1)*(n+1)+i end
  for side,a in ipairs(panel) do
    local b=panel[side%4+1]
    for k=1,3 do
      local t=k/4
      local i,j=1+t*n,1
      if side==2 then i,j=n+1,1+t*n
      elseif side==3 then i,j=n+1-t*n,n+1
      elseif side==4 then i,j=1,n+1-t*n end
      local s={point=mix(a,b,t),tangent=unit(sub(b,a)),side=side,node=node(i,j)}
      s.attraction,s.opposite=attraction(panel,s,size)
      sum_attract=sum_attract+s.attraction^2
      samples[#samples+1]=s
    end
  end
  -- The chart is convex, so every boundary sample pair is mutually visible.
  for i,a in ipairs(samples) do
    for j=i+1,#samples do
      local b=samples[j]
      local w=alignment(a.tangent,b.tangent)*distance_factor(length(sub(a.point,b.point)),size,10)
      edges[#edges+1]={i,j,w}
      sum_weights=sum_weights+2*w*w
    end
  end
  local scale=sum_attract>0 and sqrt(sum_weights/sum_attract) or 0
  local function energy(mask)
    local e=0
    for _,v in ipairs(edges) do
      if ((mask>>(v[1]-1))&1)~=((mask>>(v[2]-1))&1) then e=e+2*v[3] end
    end
    for i,s in ipairs(samples) do
      if ((mask>>(i-1))&1)==0 then e=e+omega*scale*s.attraction end
    end
    return e
  end
  local best,best_mask,count=math.huge,nil,0
  for mask=0,(1<<#samples)-1 do
    local admissible=true
    for _,lock in ipairs(fixed) do
      if ((mask>>(lock[1]-1))&1)~=lock[2] then admissible=false;break end
    end
    if admissible then
      count=count+1
      local e=energy(mask)
      if e<best-1e-12 then best,best_mask=e,mask end
    end
  end
  local active=0
  for i,s in ipairs(samples) do
    s.label=(best_mask>>(i-1))&1
    active=active+s.label
  end
  assert(active>0,"micrography-no-active-boundary")
  return {samples=samples,edges=edges,attraction_scale=scale,omega=omega,energy=best,mask=best_mask,
    examined=count,all_aligned=energy((1<<#samples)-1),none_aligned=energy(0),fixed=fixed}
end

local function mesh(panel,n)
  local points,triangles,neighbors={},{},{}
  local function node(i,j) return (j-1)*(n+1)+i end
  for j=1,n+1 do
    for i=1,n+1 do
      local u,v=(i-1)/n,(j-1)/n
      local a,b=mix(panel[1],panel[2],u),mix(panel[4],panel[3],u)
      local id=node(i,j)
      points[id]=mix(a,b,v)
      neighbors[id]={}
    end
  end
  local function add(a,b,c)
    assert(cross(sub(points[b],points[a]),sub(points[c],points[a]))>1e-10,"micrography-degenerate-triangle")
    triangles[#triangles+1]={a,b,c}
    for _,e in ipairs{{a,b},{b,c},{c,a}} do neighbors[e[1]][e[2]]=true;neighbors[e[2]][e[1]]=true end
  end
  for j=1,n do
    for i=1,n do
      local a,b,c,d=node(i,j),node(i+1,j),node(i+1,j+1),node(i,j+1)
      if (i+j)%2==0 then add(a,b,c);add(a,c,d) else add(a,b,d);add(b,c,d) end
    end
  end
  for i,adj in ipairs(neighbors) do
    local list={}
    for id in pairs(adj) do list[#list+1]=id end
    table.sort(list)
    neighbors[i]=list
  end
  return points,triangles,neighbors
end

function M.solve(panel,size,omega,fixed,n,budget,step)
  local labels=boundary(panel,size,n,omega,fixed)
  if step then step(labels.examined*(#labels.edges+#labels.samples)) end
  local points,triangles,neighbors=mesh(panel,n)
  local constraints={}
  for _,s in ipairs(labels.samples) do
    if s.label==1 then
      local x,y=table.unpack(s.tangent)
      constraints[s.node]={x*x-y*y,2*x*y}
    end
  end
  local vectors={}
  for i=1,#points do vectors[i]={1,0} end
  local residual,iterations=math.huge,0
  local function update(i)
    local c=constraints[i]
    local x,y=0,0
    if c then x,y=c[1],c[2] end
    for _,j in ipairs(neighbors[i]) do x,y=x+vectors[j][1],y+vectors[j][2] end
    local d=#neighbors[i]+(c and 1 or 0)
    return x/d,y/d
  end
  for k=1,budget do
    iterations=k
    if step then step(#points) end
    for i=1,#points do vectors[i]={update(i)} end
    residual=0
    for i=1,#points do
      local x,y=update(i)
      residual=max(residual,abs(x-vectors[i][1]),abs(y-vectors[i][2]))
    end
    if residual<1e-10 then break end
  end
  assert(residual<1e-8,"micrography-field-budget-exhausted")
  local lower,upper=math.huge,-math.huge
  for _,v in ipairs(vectors) do lower=min(lower,v[1]);upper=max(upper,v[1]) end
  assert(lower>.15,"micrography-field-not-horizontal-monotone")
  return {labels=labels,points=points,triangles=triangles,vectors=vectors,iterations=iterations,residual=residual,
    min_representation_x=lower,max_representation_x=upper}
end

function M.at(field,p)
  local points,vectors=field.points,field.vectors
  for _,t in ipairs(field.triangles) do
    local a,b,c=points[t[1]],points[t[2]],points[t[3]]
    if p[1]>=min(a[1],b[1],c[1])-1e-10 and p[1]<=max(a[1],b[1],c[1])+1e-10
        and p[2]>=min(a[2],b[2],c[2])-1e-10 and p[2]<=max(a[2],b[2],c[2])+1e-10 then
      local ab,ac,ap=sub(b,a),sub(c,a),sub(p,a)
      local d=cross(ab,ac)
      local v,w=cross(ap,ac)/d,cross(ab,ap)/d
      local u=1-v-w
      if min(u,v,w)>=-1e-9 then
        local x,y,z=vectors[t[1]],vectors[t[2]],vectors[t[3]]
        local theta=.5*math.atan(u*x[2]+v*y[2]+w*z[2],u*x[1]+v*y[1]+w*z[1])
        return {math.cos(theta),math.sin(theta)},theta
      end
    end
  end
end

return M
