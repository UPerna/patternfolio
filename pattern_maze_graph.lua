local P,H=require("pattern"),require("pattern_hash")
local Field=require("pattern_stroke_field")
local Charts=require("pattern_maze_chart")
local M={VERSION="maze-weighted-dual-tree-v1"}

local function midpoint(a,b)
  return {(a[1]+b[1])/2,(a[2]+b[2])/2}
end

local function area(a,b,c)
  return (b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1])
end

local function key(a,b)
  if P.byte_less(b,a) then a,b=b,a end
  return a.."|"..b
end

local function sorted(t)
  local out={}
  for k in pairs(t) do out[#out+1]=k end
  table.sort(out,P.byte_less)
  return out
end

function M.wall_graph(points,cells,q)
  local walls,index={},{}
  local clearance_probes={}
  for _,cell in ipairs(cells) do
    assert(not index[cell.id],"maze-duplicate-cell")
    index[cell.id]=cell
    local ids=cell.vertices
    local probes,radius={},0
    for i,a in ipairs(ids) do
      local b=ids[i%#ids+1]
      local u,v=points[a].point,points[b].point
      probes[i]={key=key(a,b),point=midpoint(u,v)}
      radius=math.max(radius,Field.distance2(cell.center,probes[i].point,probes[i].point))
      assert(area(u,v,cell.center)>1e-10,"maze-center-outside-convex-cell")
      for j,c in ipairs(ids) do
        if j~=i and j~=i%#ids+1 then assert(area(u,v,points[c].point)>1e-10,"maze-cell-not-strictly-convex") end
      end
      local id=key(a,b)
      local edge=walls[id]
      if edge then
        assert(#edge.cells==1 and edge.from==b and edge.to==a,"maze-nonmanifold-wall")
        edge.cells[2]=cell.id
      else
        edge={id="maze/wall/"..H.value("maze/wall-key",id),from=a,to=b,cells={cell.id}}
        walls[id]=edge
      end
    end
    clearance_probes[#clearance_probes+1]={center=cell.center,probes=probes,radius=math.sqrt(radius)}
  end
  local out=P.array()
  for _,k in ipairs(sorted(walls)) do
    local e=walls[k]
    local a,b=points[e.from],points[e.to]
    local u=midpoint(a.uv,b.uv)
    local g=Charts.light(q.image,u[1],u[2])
    e.light=g
    local desired,width=Charts.tone(g,q.min_wall,q.min_passage,q.max_spacing)
    e.target_spacing,e.target_width=desired,width
    local capacity=math.huge
    for _,cell in ipairs(clearance_probes) do
      local center_distance=Field.distance2(cell.center,a.point,b.point)
      local horizon=cell.radius+(width+q.min_passage)/2
      if center_distance<horizon*horizon then
        local distance=center_distance
        for _,probe in ipairs(cell.probes) do
          if probe.key~=k then
            distance=math.min(distance,Field.segment_gap2(cell.center,probe.point,a.point,b.point))
          end
        end
        capacity=math.min(capacity,2*math.sqrt(distance)-q.min_passage)
      end
    end
    assert(capacity>=q.min_wall-1e-12,"maze-minimum-physical-passage-unattainable")
    e.width=math.min(width,capacity)
    e.width_limited=e.width<width-1e-12
    e.mid=midpoint(a.point,b.point)
    local length=math.sqrt(Field.distance2(a.point,b.point,b.point))
    assert(length>=q.min_passage+q.min_wall,"maze-wall-too-short-for-passage")
    out[#out+1]=e
  end
  return out,index
end

local function bias(e,points,q)
  if q.profile=="directional" then
    local a,b=points[e.from].uv,points[e.to].uv
    return math.abs(b[1]-a[1])>math.abs(b[2]-a[2])
  elseif q.profile=="spiral" or q.profile=="vortex" then
    local a,b=points[e.from].uv,points[e.to].uv
    local r,s=(a[1]-.5)^2+(a[2]-.5)^2,(b[1]-.5)^2+(b[2]-.5)^2
    local radial=math.abs(r-s)>1e-10
    if q.profile=="vortex" then
      local m=midpoint(a,b)
      local theta=math.atan(m[2]-.5,m[1]-.5)
      return radial or math.abs(math.sin(2*theta))<.32
    end
    return radial
  end
end

local function bfs(adj,source,target,excluded)
  local queue={source}
  local parent={[source]=false}
  local n=1
  while n<=#queue and parent[target]==nil do
    local a=queue[n]
    for _,step in ipairs(adj[a]) do
      if parent[step.to]==nil and not (excluded and excluded[step.to]) then
        parent[step.to]={from=a,wall=step.wall}
        queue[#queue+1]=step.to
      end
    end
    n=n+1
  end
  if parent[target]==nil then return nil end
  local vertices,edges={target},{}
  local cursor=target
  while parent[cursor] do
    local e=parent[cursor]
    edges[#edges+1]=e.wall
    vertices[#vertices+1]=e.from
    cursor=e.from
  end
  local v,w=P.array(),P.array()
  for i=#vertices,1,-1 do v[#v+1]=vertices[i] end
  for i=#edges,1,-1 do w[#w+1]=edges[i] end
  return v,w
end

local function terminal(walls,target,forbid)
  local nearest,best=nil,math.huge
  for _,e in ipairs(walls) do
    if #e.cells==1 and (not forbid or forbid.id~=e.id and forbid.cells[1]~=e.cells[1]) then
      local d=Field.distance2(target,e.mid,e.mid)
      if d<best-1e-12 then nearest,best=e,d end
    end
  end
  assert(nearest,"maze-distinct-boundary-endpoints-required")
  return nearest
end

local function closest_cell(cells,p)
  local best,chosen=math.huge
  for _,cell in ipairs(cells) do
    local d=Field.distance2(p,cell.center,cell.center)
    if d<best-1e-12 then best,chosen=d,cell.id end
  end
  return chosen
end

local function link(adj,e)
  local a,b=table.unpack(e.cells)
  adj[a][#adj[a]+1]={to=b,wall=e}
  adj[b][#adj[b]+1]={to=a,wall=e}
end

function M.route(points,cells,walls,q,rng)
  assert(#cells>=2,"maze-insufficient-cells")
  local adj,tree,parents,depth={},{},{},{}
  for _,c in ipairs(cells) do adj[c.id]={};tree[c.id]={};parents[c.id]=c.id;depth[c.id]=1 end
  local function root(a)
    while parents[a]~=a do
      parents[a]=parents[parents[a]]
      a=parents[a]
    end
    return a
  end
  local function join(e)
    local a,b=root(e.cells[1]),root(e.cells[2])
    if a==b then return false end
    if depth[a]<depth[b] then a,b=b,a end
    parents[b]=a
    if depth[a]==depth[b] then depth[a]=depth[a]+1 end
    e.open=true
    link(tree,e)
    return true
  end
  local candidates={}
  for _,e in ipairs(walls) do
    e.open=false
    if #e.cells==2 then
      local sample=rng.u()
      local favored=bias(e,points,q)
      e.bias=favored==nil and "isotropic" or (favored and "preferred-removal" or "preferred-retention")
      local strength=q.guided and q.bias or 0
      if favored==nil then e.weight=sample
      elseif favored then e.weight=sample*(1-strength)
      else e.weight=strength+sample*(1-strength) end
      e.random=sample
      candidates[#candidates+1]=e
      link(adj,e)
    end
  end
  local entry=terminal(walls,q.entry)
  local exit=terminal(walls,q.exit,entry)
  local pin_count=0
  local pins=P.array()
  if #q.guide>0 then
    local waypoints={entry.cells[1]}
    for _,p in ipairs(q.guide) do waypoints[#waypoints+1]=closest_cell(cells,p) end
    waypoints[#waypoints+1]=exit.cells[1]
    local reserved={}
    for i=1,#waypoints do
      assert(not reserved[waypoints[i]],"maze-guide-repeats-cell")
      reserved[waypoints[i]]=true
    end
    local visited={}
    for i=1,#waypoints-1 do
      local from,to=waypoints[i],waypoints[i+1]
      reserved[from],reserved[to]=nil,nil
      local blocked={}
      for k in pairs(reserved) do blocked[k]=true end
      for k in pairs(visited) do blocked[k]=true end
      blocked[from]=nil
      local vertices,edges=bfs(adj,from,to,blocked)
      assert(vertices,"maze-guide-infeasible")
      for _,k in ipairs(vertices) do visited[k]=true end
      for _,e in ipairs(edges) do
        assert(join(e),"maze-guide-cycle")
        e.guide=true
        pins[#pins+1]=e.id
        pin_count=pin_count+1
      end
    end
  end
  table.sort(candidates,function(a,b)
    local x,y=math.floor(a.weight*1e12+.5),math.floor(b.weight*1e12+.5)
    if x==y then return P.byte_less(a.id,b.id) end
    return x<y
  end)
  local open=pin_count
  for _,e in ipairs(candidates) do if join(e) then open=open+1 end end
  assert(open==#cells-1,"maze-disconnected-domain")
  entry.open,exit.open=true,true
  entry.terminal,exit.terminal="entry","exit"
  local route,crossings=bfs(tree,entry.cells[1],exit.cells[1])
  assert(route and #route>=2,"maze-endpoints-unreachable")
  local ids=P.array()
  for i,e in ipairs(crossings) do ids[i]=e.id end
  return {entry=entry.id,exit=exit.id,route=route,crossings=ids,guide=pins,passages=open,
    objective="minimum-weight-spanning-tree-with-pinned-guide",weight_tie_resolution=1e-12}
end

return M
