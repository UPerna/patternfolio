local P,R,H=require("pattern"),require("pattern_registry"),require("pattern_hash")
local F,C,G=require("pattern_stroke_field"),require("pattern_maze_chart"),require("pattern_maze_graph")
local Penrose=require("pattern_penrose")
local M={VERSION="image-guided-perfect-maze-v1"}

local function configuration(s)
  local a,b=s.parameters,s.document.bounds
  local w,h=b[3]-b[1],b[4]-b[2]
  assert(w>=2 and h>=2 and w<=25 and h<=25,"maze-document-bounds")
  assert(next(P.plain(s.constraints))==nil,"maze-unsupported-constraints")
  for k in pairs(s.inputs) do assert(k=="entry" or k=="exit" or k=="guide" or k=="holes","maze-input:"..k) end
  local function point(p)
    local v=F.point(p)
    assert(v[1]>=b[1] and v[1]<=b[3] and v[2]>=b[2] and v[2]<=b[4],"maze-point-outside-document")
    return v
  end
  local entry=point(s.inputs.entry or {b[1],b[2]+h*.26})
  local exit=point(s.inputs.exit or {b[3],b[2]+h*.74})
  assert(F.distance2(entry,exit,exit)>.01,"maze-endpoint-targets-not-distinct")
  local guide=P.array()
  if s.inputs.guide then
    assert(type(s.inputs.guide)=="table" and #s.inputs.guide>=1 and #s.inputs.guide<=12,"maze-guide-count")
    for i,p in ipairs(s.inputs.guide) do guide[i]=point(p) end
  end
  local holes=P.array()
  if s.inputs.holes then
    assert(a.profile=="holed" and type(s.inputs.holes)=="table" and #s.inputs.holes<=10,"maze-holes-profile")
    for i,v in ipairs(s.inputs.holes) do
      assert(#v==3 and F.finite(v[1]) and F.finite(v[2]) and F.finite(v[3])
        and v[1]>0 and v[1]<1 and v[2]>0 and v[2]<1 and v[3]>0 and v[3]<.8,"maze-hole-unit-chart")
      holes[i]=P.plain(v)
    end
  end
  local q={bounds=P.plain(b),profile=a.profile,image=a.image or "ramp",cols=a.columns or 22,rows=a.rows or 15,
    min_wall=a.min_wall or .013,min_passage=a.min_passage or .035,max_spacing=a.max_spacing or .48,
    guided=a.guided~=false,bias=a.bias or .62,relax=a.relax or 6,perspective=a.perspective or 0,
    edge_length=a.edge_length or .44,notch=a.notch or false,entry=entry,exit=exit,guide=guide,holes=holes}
  assert(q.max_spacing>q.min_wall+q.min_passage,"maze-tone-range")
  assert(q.cols*q.rows<=650,"maze-cell-budget")
  assert(q.profile~="aperiodic" or q.perspective==0,"maze-aperiodic-perspective-unsupported")
  return q
end

local function penrose(reg,d,s,c,q)
  local b=q.bounds
  local spec={id="maze/aperiodic-source",definition_ref={id=d.id,version=d.version},seed=s.seed,
    parameters={edge_length=q.edge_length,phase="amber"},inputs={},style={},constraints={},budget=P.plain(s.budget),
    document={unit="cm",bounds=b,protected_regions=P.array()}}
  local result,err=reg:generate(d.id,spec,c)
  assert(result,err and P.serialize(err))
  local source=result.instance
  local t=source.structures.tiling
  local edges,points,cells={},{},{}
  for _,e in ipairs(t.edges) do edges[e.id]=e end
  for _,v in ipairs(t.vertices) do
    points[v.id]={point=P.plain(v.point),uv={(v.point[1]-b[1])/(b[3]-b[1]),(v.point[2]-b[2])/(b[4]-b[2])}}
  end
  for _,v in ipairs(t.cells) do
    local ids,inside,x,y={},true,0,0
    for j,e in ipairs(v.boundary) do
      local edge=edges[e.edge]
      local id=e.reversed and edge.to or edge.from
      local p=points[id].uv
      if p[1]<.02 or p[1]>.98 or p[2]<.02 or p[2]>.98 then inside=false end
      ids[j]=id
      x,y=x+p[1]/4,y+p[2]/4
    end
    if inside then
      cells[#cells+1]={id=v.id,vertices=ids,center={b[1]+x*(b[3]-b[1]),b[2]+y*(b[4]-b[2])},
        light=C.light(q.image,x,y),source_ref=v.id}
    end
  end
  return points,cells,{profile="aperiodic",scaffold_ref=source.id,phase=source.extensions.penrose.request.phase,
    source_cells=#t.cells,selection="complete rhombi with inset rectangular corner test"}
end

function M.definition()
  return P.definition({id="maze/image-guided",version="1",family="image-guided-dual-tree-maze",
    units="cm",capabilities={"graph"},parameters={
      profile={type="string",enum={"directional","spiral","vortex","random","holed","aperiodic"},required=true},
      image={type="string",enum={"ramp","radial","ribbon","constant"}},columns={type="integer",minimum=4,maximum=45},
      rows={type="integer",minimum=3,maximum=32},min_wall={type="number",minimum=.005,maximum=.08},
      min_passage={type="number",minimum=.018,maximum=.14},max_spacing={type="number",minimum=.15,maximum=.95},
      guided={type="boolean"},bias={type="number",minimum=0,maximum=.9},relax={type="integer",minimum=0,maximum=20},
      perspective={type="number",minimum=0,maximum=.65},edge_length={type="number",minimum=.27,maximum=.9},
      notch={type="boolean"}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Finite embedded cell graph and positively separated wall geometry",
      "Image-derived spacing and widths, controlled routing bias and a simple pinned-route profile",
      "Perfect full maze, with display-only crops and separate aperiodic/holed extensions"}})
end

local function graph(points,cells,walls)
  local vertices,edges=P.array(),P.array()
  local cell_index={}
  for i,c in ipairs(cells) do
    vertices[i]={id=c.id,point=c.center}
    cell_index[c.id]=true
  end
  for _,w in ipairs(walls) do
    if w.open then
      local a,b=table.unpack(w.cells)
      if not b then
        b="maze/terminal/"..w.terminal
        vertices[#vertices+1]={id=b,point=w.mid}
      end
      edges[#edges+1]={id=w.id,from=a,to=b}
    end
  end
  return {vertices=vertices,edges=edges}
end

local function validate(x)
  local e=x.extensions.maze
  local rebuilt=G.wall_graph(e.points,e.cells,e.request)
  assert(#rebuilt==#e.walls,"maze-wall-count")
  local open,terminal=0,{}
  local by_id={}
  for i,w in ipairs(e.walls) do
    local a=rebuilt[i]
    for k,v in pairs(a) do assert(P.serialize(v)==P.serialize(w[k]),"maze-wall-reconstruction:"..k) end
    by_id[w.id]=w
    if w.open then
      if #w.cells==2 then open=open+1
      else
        assert((w.terminal=="entry" or w.terminal=="exit") and not terminal[w.terminal],"maze-terminal-incidence")
        terminal[w.terminal]=w.id
      end
    end
  end
  local s=e.solution
  assert(open==#e.cells-1 and s.passages==open and s.entry==terminal.entry and s.exit==terminal.exit,"maze-passage-count")
  local g=graph(e.points,e.cells,e.walls)
  assert(P.serialize(g)==P.serialize(x.structures.graph),"maze-passage-graph-reconstruction")
  local adjacency={}
  for _,v in ipairs(g.vertices) do adjacency[v.id]={} end
  for _,a in ipairs(g.edges) do
    local u,v=adjacency[a.from],adjacency[a.to]
    u[#u+1]=a.to;v[#v+1]=a.from
  end
  local queue,visited={"maze/terminal/entry"},{["maze/terminal/entry"]=true}
  local i=1
  while i<=#queue do
    for _,v in ipairs(adjacency[queue[i]]) do
      if not visited[v] then visited[v]=true;queue[#queue+1]=v end
    end
    i=i+1
  end
  assert(#queue==#g.vertices,"maze-disconnected-passage-graph")
  assert(#s.crossings==#s.route-1 and s.route[1]==by_id[s.entry].cells[1]
    and s.route[#s.route]==by_id[s.exit].cells[1],"maze-solution-endpoints")
  local marked,route_cells={},{ }
  for i,v in ipairs(s.route) do assert(not route_cells[v],"maze-route-cycle");route_cells[v]=true end
  for i,id in ipairs(s.crossings) do
    local w=assert(by_id[id],"maze-missing-solution-wall")
    assert(w.open and #w.cells==2 and ((w.cells[1]==s.route[i] and w.cells[2]==s.route[i+1])
      or (w.cells[2]==s.route[i] and w.cells[1]==s.route[i+1])),"maze-solution-crosses-wall")
    marked[id]=true
  end
  for _,id in ipairs(s.guide) do assert(marked[id],"maze-solution-skips-guide") end
  return {ok=true,checks={"Convex cell incidences and physical wall limits reconstructed",
    "Connected passage graph with tree edge count","Unique route uses only real openings"},
    construction={cells=#e.cells,passages=open,route_cells=#s.route}}
end

local function lower(x,v,style)
  for k in pairs(style) do assert(k=="display","maze-style:"..k) end
  local display=style.display or "walls"
  assert(display=="walls" or display=="solution","maze-display")
  local e=x.extensions.maze
  local ops,by_wall=P.array(),{}
  local function path(ref,points,width,color)
    local p={}
    for i,v in ipairs(points) do p[i]={i==1 and "M" or "L",v[1],v[2]} end
    ops[#ops+1]={op="path",semantic_ref=ref,commands=p,transform=P.plain(v.transform),
      paint={stroke=color,stroke_width=width,cap="round",join="round"}}
  end
  for _,w in ipairs(e.walls) do
    by_wall[w.id]=w
    if not w.open then path(x.id,{e.points[w.from].point,e.points[w.to].point},w.width,{.10,.16,.21}) end
  end
  if display=="solution" then
    local cells={}
    for _,c in ipairs(e.cells) do cells[c.id]=c.center end
    local s=e.solution
    local points={by_wall[s.entry].mid}
    for i,id in ipairs(s.route) do
      points[#points+1]=cells[id]
      if s.crossings[i] then points[#points+1]=by_wall[s.crossings[i]].mid end
    end
    points[#points+1]=by_wall[s.exit].mid
    path(x.id,points,e.request.min_passage*.45,{.75,.23,.12})
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,operations=ops,
    resources=P.array(),clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)}}
end

function M.register(reg)
  local d=M.definition()
  local source=R.new()
  local pd=Penrose.register(source)
  reg:register(d,{validate_inputs=function(s) configuration(s);return true end,generate=function(s,c)
    local q=configuration(s)
    local points,cells,chart
    if q.profile=="aperiodic" then points,cells,chart=penrose(source,pd,s,c,q)
    else points,cells,chart=C.build(q,c:stream("maze-embedding",q.profile)) end
    local walls=G.wall_graph(points,cells,q)
    c:consume("objects",#walls+#cells)
    c:consume("operations",#walls*4+#cells*4)
    local solution=G.route(points,cells,walls,q,c:stream("maze-wall-order","kruskal"))
    return {id="maze/"..H.value("maze/design",{q=q,seed=s.seed,method=M.VERSION}),
      definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={graph=graph(points,cells,walls)},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={maze={request=q,points=points,cells=P.array(cells),walls=walls,chart=chart,solution=solution,
        guarantee="unique full-maze route; crop is display only"}}}
  end,validate=validate,lower=lower})
  return d
end

return M
