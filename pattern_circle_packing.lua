-- Bounded numerical circle packing for an oriented triangulated disk.
local P=require("pattern")
local M={VERSION="disk-angle-bisection-v1"}
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function sort_keys(t)
  local ids={}
  for k in pairs(t) do ids[#ids+1]=k end
  table.sort(ids,P.byte_less)
  return ids
end
local function edge_key(a,b)
  if P.byte_less(a,b) then return a.."/"..b else return b.."/"..a end
end
local function join(map,a,b)
  map[a]=map[a] or {}
  map[a][b]=true
end
local function reach(neighbors,start)
  local seen,q={[start]=true},{start}
  local i=1
  while i<=#q do
    for v in pairs(neighbors[q[i]] or {}) do
      if not seen[v] then seen[v]=true;q[#q+1]=v end
    end
    i=i+1
  end
  return #q
end

function M.disk(complex)
  assert(type(complex)=="table" and type(complex.faces)=="table"
    and #complex.faces>=3 and #complex.faces<=120,"packing-face-budget")
  local vertices,edges,adjacent,links={}, {}, {}, {}
  local faces,face_keys={},{}
  for i,f in ipairs(complex.faces) do
    assert(type(f)=="table" and #f==3,"packing-triangle-size")
    for _,v in ipairs(f) do
      assert(type(v)=="string" and #v<=32 and v:match("^[%w_-]+$"),"packing-vertex-id")
      vertices[v]=true
    end
    local a,b,c=table.unpack(f)
    assert(a~=b and b~=c and c~=a,"packing-degenerate-triangle")
    local sorted={a,b,c};table.sort(sorted,P.byte_less)
    local triangle_key=table.concat(sorted,"/")
    assert(not face_keys[triangle_key],"packing-duplicate-triangle")
    face_keys[triangle_key]=true
    faces[i]={a,b,c}
    for j=1,3 do
      local u,v,w=f[j],f[j%3+1],f[(j+1)%3+1]
      local key=edge_key(u,v)
      local e=edges[key]
      if not e then edges[key]={from=u,to=v,faces={i}}
      else
        assert(#e.faces==1 and e.from==v and e.to==u,"packing-edge-incidence-or-orientation")
        e.faces[2]=i
      end
      join(adjacent,u,v);join(adjacent,v,u)
      links[u]=links[u] or {}
      join(links[u],v,w);join(links[u],w,v)
    end
  end
  local ids,edge_ids=sort_keys(vertices),sort_keys(edges)
  assert(#ids<=72 and #ids-#edge_ids+#faces==1,"packing-disk-euler")
  assert(reach(adjacent,ids[1])==#ids,"packing-disconnected-disk")
  local boundary,boundary_adjacent={},{}
  for _,e in pairs(edges) do
    if #e.faces==1 then
      boundary[e.from],boundary[e.to]=true,true
      join(boundary_adjacent,e.from,e.to);join(boundary_adjacent,e.to,e.from)
    end
  end
  local border=sort_keys(boundary)
  assert(#border>=3 and reach(boundary_adjacent,border[1])==#border,"packing-boundary-cycle")
  local interior={}
  for _,u in ipairs(ids) do
    local ring=sort_keys(adjacent[u])
    assert(#ring>=3 and reach(links[u],ring[1])==#ring,"packing-vertex-link")
    local ends=0
    for _,v in ipairs(ring) do
      local n=#sort_keys(links[u][v])
      assert(n==1 or n==2,"packing-link-degree")
      if n==1 then ends=ends+1 end
    end
    if boundary[u] then
      assert(ends==2 and #sort_keys(boundary_adjacent[u])==2,"packing-boundary-link")
    else
      assert(ends==0,"packing-interior-link")
      interior[#interior+1]=u
    end
  end
  assert(#interior>0,"packing-requires-interior-vertex")
  return {ids=ids,faces=faces,edges=edges,edge_ids=edge_ids,adjacent=adjacent,links=links,boundary=boundary,interior=interior}
end

local function angle(ri,rj,rk)
  return 2*math.asin(math.sqrt(rj*rk/((ri+rj)*(ri+rk))))
end
local function angle_sum(r,ri,pairs)
  local out=0
  for _,pair in ipairs(pairs) do out=out+angle(ri,r[pair[1]],r[pair[2]]) end
  return out
end
local function solve_radii(d,tol,maximum,poll)
  local radii,neighbors={},{}
  for _,id in ipairs(d.ids) do
    local n=#sort_keys(d.adjacent[id])
    radii[id]=d.boundary[id] and (1/math.sin(math.pi/(2*n-2))-1) or 1
    neighbors[id]={}
  end
  for _,f in ipairs(d.faces) do
    for j=1,3 do
      local u,v,w=f[j],f[j%3+1],f[(j+1)%3+1]
      neighbors[u][#neighbors[u]+1]={v,w}
    end
  end
  for iteration=1,maximum do
    if poll then poll(#d.faces*180) end
    for _,u in ipairs(d.interior) do
      local lo,hi=1e-6,1e6
      assert(angle_sum(radii,lo,neighbors[u])>2*math.pi and angle_sum(radii,hi,neighbors[u])<2*math.pi,
        "packing-radius-bracket")
      for _=1,60 do
        local mid=math.sqrt(lo*hi)
        if angle_sum(radii,mid,neighbors[u])>2*math.pi then lo=mid else hi=mid end
      end
      radii[u]=math.sqrt(lo*hi)
    end
    local max_residual=0
    for _,u in ipairs(d.interior) do
      max_residual=math.max(max_residual,math.abs(angle_sum(radii,radii[u],neighbors[u])-2*math.pi))
    end
    if max_residual<=tol then return radii,iteration,max_residual end
  end
  error("packing-nonconvergence")
end

local function distance(a,b)
  return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)
end
local function embed(d,r)
  local root=d.faces[1]
  local first,second=root[1],root[2]
  local points={[first]={0,0},[second]={r[first]+r[second],0}}
  local count=2
  while count<#d.ids do
    local previous=count
    for _,f in ipairs(d.faces) do
      for i=1,3 do
        local a,b,c=f[i],f[i%3+1],f[(i+1)%3+1]
        if points[a] and points[b] and not points[c] then
          local A,B=points[a],points[b]
          local ab,ac,bc=distance(A,B),r[a]+r[c],r[b]+r[c]
          local ux,uy=(B[1]-A[1])/ab,(B[2]-A[2])/ab
          local x=(ab*ab+ac*ac-bc*bc)/(2*ab)
          local square=ac*ac-x*x
          assert(square>0,"packing-embedding-degenerate")
          local y=math.sqrt(square)
          points[c]={A[1]+x*ux-y*uy,A[2]+x*uy+y*ux}
          count=count+1
        end
      end
    end
    assert(previous<count,"packing-embedding-disconnected")
  end
  return points,{first,second}
end

function M.solve(complex,settings)
  local disk=M.disk(complex)
  local tol,cap=settings.tolerance or 1e-11,settings.iterations or 600
  assert(finite(tol) and tol>=1e-13 and tol<=1e-7,"packing-tolerance")
  assert(type(cap)=="number" and cap%1==0 and cap>=1 and cap<=3000,"packing-iteration-budget")
  local radius,iterations,angular_residual=solve_radii(disk,tol,cap,settings.poll)
  local centers,root=embed(disk,radius)
  local lo_x,lo_y,hi_x,hi_y=math.huge,math.huge,-math.huge,-math.huge
  for _,id in ipairs(disk.ids) do
    local p,r=centers[id],radius[id]
    lo_x,lo_y=math.min(lo_x,p[1]-r),math.min(lo_y,p[2]-r)
    hi_x,hi_y=math.max(hi_x,p[1]+r),math.max(hi_y,p[2]+r)
  end
  local scale,tx,ty=1,0,0
  local panel=settings.panel
  if panel then
    assert(#panel==4 and finite(panel[1]) and finite(panel[2]) and finite(panel[3]) and finite(panel[4])
      and panel[3]>panel[1] and panel[4]>panel[2],"packing-panel")
    scale=math.min((panel[3]-panel[1])/(hi_x-lo_x),(panel[4]-panel[2])/(hi_y-lo_y))
    tx=(panel[1]+panel[3]-scale*(lo_x+hi_x))/2
    ty=(panel[2]+panel[4]-scale*(lo_y+hi_y))/2
  end
  local circles={}
  for _,id in ipairs(disk.ids) do
    local p=centers[id]
    circles[id]={center={scale*p[1]+tx,scale*p[2]+ty},radius=scale*radius[id],
      degree=#sort_keys(disk.adjacent[id]),boundary=disk.boundary[id] or false}
  end
  local edge_error,clearance=0,math.huge
  for i,a in ipairs(disk.ids) do
    for j=i+1,#disk.ids do
      local b=disk.ids[j]
      local A,B=circles[a],circles[b]
      local gap=distance(A.center,B.center)-A.radius-B.radius
      if disk.edges[edge_key(a,b)] then edge_error=math.max(edge_error,math.abs(gap))
      else clearance=math.min(clearance,gap) end
    end
  end
  assert(edge_error<=scale*tol*120+1e-12,"packing-tangency-residual")
  assert(clearance>scale*tol*120+1e-12,"packing-nonedge-contact-or-overlap")
  local N=require("pattern_predicates")
  for _,f in ipairs(disk.faces) do
    assert(N.orient2d(circles[f[1]].center,circles[f[2]].center,circles[f[3]].center)>0,"packing-embedding-orientation")
  end
  return {circles=circles,solver=M.VERSION,converged=true,iterations=iterations,tolerance=tol,
    maximum_angular_residual=angular_residual,maximum_tangency_residual=edge_error,minimum_nonedge_clearance=clearance<math.huge and clearance or nil,
    normalization={scale=scale,translation={tx,ty},root=root,panel=panel},complex={faces=disk.faces}}
end

-- Read-only certificate validation for offline results. It deliberately does
-- not iterate radii or place centers.
function M.validate(record)
  assert(record.solver==M.VERSION and record.converged==true,"packing-solver-certificate")
  local tol=record.tolerance
  assert(finite(tol) and tol>=1e-13 and tol<=1e-7,"packing-tolerance")
  assert(type(record.iterations)=="number" and record.iterations%1==0
    and record.iterations>=1 and record.iterations<=3000,"packing-iteration-receipt")
  local d=M.disk(record.complex)
  local circles=record.circles
  assert(#sort_keys(circles)==#d.ids,"packing-circle-count")
  local n=record.normalization
  assert(finite(n.scale) and n.scale>0 and #n.translation==2 and finite(n.translation[1]) and finite(n.translation[2]),
    "packing-normalization")
  assert(n.root[1]==d.faces[1][1] and n.root[2]==d.faces[1][2],"packing-root")
  local epsilon=n.scale*tol*120+1e-12
  for _,id in ipairs(d.ids) do
    local c=assert(circles[id],"packing-missing-circle")
    local degree=#sort_keys(d.adjacent[id])
    assert(c.degree==degree and c.boundary==(d.boundary[id] or false),"packing-circle-correspondence")
    assert(finite(c.radius) and c.radius>0 and finite(c.center[1]) and finite(c.center[2]),"packing-circle-coordinate")
    if c.boundary then
      assert(math.abs(c.radius-n.scale*(1/math.sin(math.pi/(2*degree-2))-1))<=epsilon,"packing-boundary-radius")
    end
    if n.panel then
      local x,y=table.unpack(c.center)
      local r=c.radius
      assert(x-r>=n.panel[1]-epsilon and y-r>=n.panel[2]-epsilon
        and x+r<=n.panel[3]+epsilon and y+r<=n.panel[4]+epsilon,"packing-panel-containment")
    end
  end
  assert(distance(circles[n.root[1]].center,n.translation)<=epsilon,"packing-root-translation")
  local A,B=circles[n.root[1]].center,circles[n.root[2]].center
  assert(B[1]>A[1] and math.abs(B[2]-A[2])<=epsilon,"packing-root-axis")
  local edge_error,clearance=0,math.huge
  for i,a in ipairs(d.ids) do
    for j=i+1,#d.ids do
      local b=d.ids[j]
      local C,D=circles[a],circles[b]
      local gap=distance(C.center,D.center)-C.radius-D.radius
      if d.edges[edge_key(a,b)] then edge_error=math.max(edge_error,math.abs(gap))
      else clearance=math.min(clearance,gap) end
    end
  end
  assert(edge_error<=epsilon and math.abs(edge_error-record.maximum_tangency_residual)<=epsilon,"packing-tangency-residual")
  if clearance==math.huge then
    assert(record.minimum_nonedge_clearance==nil,"packing-nonedge-clearance-receipt")
  else
    assert(clearance>epsilon and finite(record.minimum_nonedge_clearance)
      and math.abs(clearance-record.minimum_nonedge_clearance)<=epsilon,"packing-nonedge-contact-or-overlap")
  end
  local N=require("pattern_predicates")
  -- Compensated accumulation preserves the existing strict certificate bound
  -- when a high-valence wheel's normalized angles are added. The ordinary
  -- sum falsely rejected an admitted60-fan (1.78e-14 versus8.88e-15 with
  -- compensated addition); circles, solver and tolerances are unchanged.
  local sums,correction={},{}
  for _,f in ipairs(d.faces) do
    assert(N.orient2d(circles[f[1]].center,circles[f[2]].center,circles[f[3]].center)>0,"packing-embedding-orientation")
    for i=1,3 do
      local a,b,c=f[i],f[i%3+1],f[(i+1)%3+1]
      local value=angle(circles[a].radius,circles[b].radius,circles[c].radius)
      local adjusted=value-(correction[a]or 0)
      local total=(sums[a]or 0)+adjusted
      correction[a]=(total-(sums[a]or 0))-adjusted;sums[a]=total
    end
  end
  local residual=0
  for _,id in ipairs(d.interior) do residual=math.max(residual,math.abs(sums[id]-2*math.pi)) end
  assert(residual<=tol+1e-14 and math.abs(residual-record.maximum_angular_residual)<=1e-14,"packing-angular-residual")
  return true
end

return M
