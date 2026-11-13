-- Deterministic finite marked-square completion. The assignment verifier
-- does not depend on the search order or on the searcher's success flag.
local P,H=require("pattern"),require("pattern_hash")
local M={VERSION="finite-marked-square-search-v1"}
local names={"north","east","south","west"}
local directions={{0,1},{1,0},{0,-1},{-1,0}}
local opposite={3,4,1,2}
local variants={
  {id="blank",marks={0,0,0,0}},
  {id="straight-ns",marks={1,0,1,0}},
  {id="straight-ew",marks={0,1,0,1}},
  {id="elbow-ne",marks={1,1,0,0}},
  {id="elbow-es",marks={0,1,1,0}},
  {id="elbow-sw",marks={0,0,1,1}},
  {id="elbow-wn",marks={1,0,0,1}},
}
local by_id,side_index={},{}
for _,tile in ipairs(variants) do by_id[tile.id]=tile end
for i,name in ipairs(names) do side_index[name]=i end
local function key(x,y) return x.."/"..y end
local function integer(n,lo,hi) return type(n)=="number" and n%1==0 and n>=lo and n<=hi end
local function fields(t,allowed)
  assert(type(t)=="table","constraint-object-required")
  for k in pairs(t) do assert(allowed[k],"constraint-unknown-field:"..tostring(k)) end
end
local function sequence(t)
  assert(type(t)=="table","constraint-array-required")
  local count=0
  for i in pairs(t) do
    assert(integer(i,1,#t),"constraint-dense-array-required")
    count=count+1
  end
  assert(count==#t,"constraint-dense-array-required")
  return t
end
local function coordinate(p,w,h)
  sequence(p)
  assert(type(p)=="table" and #p==2 and integer(p[1],1,w) and integer(p[2],1,h),"constraint-grid-coordinate")
  return key(p[1],p[2])
end
local function normalize(problem)
  fields(problem,{width=true,height=true,holes=true,boundary=true})
  local w,h=problem.width,problem.height
  assert(integer(w,1,6) and integer(h,1,6),"constraint-grid-size")
  local holes,cells,by_key={},P.array(),{}
  for _,p in ipairs(sequence(problem.holes or {})) do
    local id=coordinate(p,w,h)
    assert(not holes[id],"constraint-duplicate-hole")
    holes[id]=true
  end
  for y=1,h do for x=1,w do
    local id=key(x,y)
    if not holes[id] then
      local c={id=id,x=x,y=y}
      cells[#cells+1]=c;by_key[id]=c
    end
  end end
  assert(#cells>0,"constraint-empty-occupancy")
  local override={}
  for _,r in ipairs(sequence(problem.boundary or {})) do
    fields(r,{cell=true,side=true,mark=true})
    local id=coordinate(r.cell,w,h)
    local c,i=by_key[id],side_index[r.side]
    assert(c and i and integer(r.mark,0,1),"constraint-boundary-record")
    local d=directions[i]
    assert(not by_key[key(c.x+d[1],c.y+d[2])],"constraint-boundary-on-interior")
    local k=id.."/"..r.side
    assert(override[k]==nil,"constraint-duplicate-boundary")
    override[k]=r.mark
  end
  for _,c in ipairs(cells) do
    c.sides={}
    for i,d in ipairs(directions) do
      local n=by_key[key(c.x+d[1],c.y+d[2])]
      c.sides[i]=n and {neighbor=n.id} or {fixed=override[c.id.."/"..names[i]] or 0}
    end
  end
  return {width=w,height=h,occupied=cells}
end
local function check_assignment(problem,assignment)
  assert(#sequence(assignment)==#problem.occupied,"constraint-incomplete-assignment")
  local placed={}
  for i,c in ipairs(problem.occupied) do
    local item=assignment[i]
    fields(item,{cell=true,tile=true})
    assert(type(item)=="table" and item.cell==c.id and by_id[item.tile] and not placed[item.cell],"constraint-invalid-assignment")
    placed[c.id]=by_id[item.tile]
  end
  for _,c in ipairs(problem.occupied) do
    for i,s in ipairs(c.sides) do
      local mark=placed[c.id].marks[i]
      local required=s.neighbor and placed[s.neighbor].marks[opposite[i]] or s.fixed
      assert(mark==required,"constraint-mark-mismatch:"..c.id.."/"..names[i])
    end
  end
  return true
end
local function build_receipt(problem,options,route)
  assert(integer(options.seed,0,2^31-1) and integer(options.node_limit,0,200000),"constraint-solver-limits")
  assert(options.deadline_ms==nil or integer(options.deadline_ms,1,5000),"constraint-deadline")
  return {algorithm=M.VERSION,route=route,seed=options.seed,node_limit=options.node_limit,
    deadline_ms=options.deadline_ms,problem_sha256=H.value("constraint/problem",problem),
    order="row-major, fixed oriented tile order",nodes=0}
end
local function search(problem,options,context,clock)
  local receipt=build_receipt(problem,options,"searched")
  local deadline
  if options.deadline_ms then
    assert(type(clock)=="function","constraint-clock-required")
    deadline=clock()+options.deadline_ms/1000
  end
  local placed={}
  local function choose(index)
    if deadline and clock()>=deadline then return "timeout" end
    if index>#problem.occupied then return "complete" end
    if receipt.nodes>=options.node_limit then return "unknown" end
    receipt.nodes=receipt.nodes+1
    local cell=problem.occupied[index]
    for _,tile in ipairs(variants) do
      if context then context:consume("operations",1) end
      local legal=true
      for i,s in ipairs(cell.sides) do
        local neighbor=s.neighbor and placed[s.neighbor]
        local required=neighbor and neighbor.marks[opposite[i]] or s.fixed
        if required~=nil and tile.marks[i]~=required then legal=false;break end
      end
      if legal then
        placed[cell.id]=tile
        local result=choose(index+1)
        if result~="unsatisfiable" then return result end
        placed[cell.id]=nil
      end
    end
    return "unsatisfiable"
  end
  receipt.status=choose(1)
  local assignment
  if receipt.status=="complete" then
    assignment=P.array()
    for i,c in ipairs(problem.occupied) do assignment[i]={cell=c.id,tile=placed[c.id].id} end
    check_assignment(problem,assignment)
    receipt.assignment_sha256=H.value("constraint/assignment",assignment)
  end
  return {problem=problem,assignment=assignment,receipt=receipt}
end
local function replay(problem,options,assignment)
  check_assignment(problem,assignment)
  local receipt=build_receipt(problem,options,"replayed")
  receipt.status="complete"
  receipt.assignment_sha256=H.value("constraint/assignment",assignment)
  return {problem=problem,assignment=P.plain(assignment),receipt=receipt}
end
local function routes(clock)
  local r=require("pattern_aperiodic").route_registry()
  r.register("bounded_constraint",{
    construct=function(request,context)
      local problem=normalize(request.problem)
      if request.assignment then return replay(problem,request.options,request.assignment) end
      return search(problem,request.options,context,clock)
    end,
    validate=function(result)
      if result.receipt.status=="complete" then return check_assignment(result.problem,result.assignment) end
      return result.assignment==nil and
        (result.receipt.status=="unknown" or result.receipt.status=="timeout" or result.receipt.status=="unsatisfiable")
    end})
  return r
end
function M.definition()
  return P.definition({id="tiling/marked-square-completion",version="1",family="finite-marked-square",
    units="cm",capabilities={"graph"},parameters={cell_size={type="number",minimum=.25,maximum=2,required=true},
      node_limit={type="integer",minimum=0,maximum=200000},deadline_ms={type="integer",minimum=1,maximum=5000}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Exactly one admitted oriented square in each occupied slot",
      "Edges meet equal binary marks and boundary constraints are fixed",
      "Finite completion with explicit search limits"}})
end
local function geometry(problem,assignment,frame,step,prefix)
  local vertices,edges,points=P.array(),P.array(),{}
  local function vertex(ix,iy)
    local suffix=key(ix,iy)
    local id=prefix.."/v/"..suffix
    if not points[id] then
      points[id]={id=id,point={frame.origin[1]+ix*step/2,frame.origin[2]+iy*step/2},grid={ix,iy}}
      vertices[#vertices+1]=points[id]
    end
    return id
  end
  local placements=P.array()
  for i,c in ipairs(problem.occupied) do
    local x,y=2*c.x-1,2*c.y-1
    local center=vertex(x,y)
    local tile=by_id[assignment[i].tile]
    placements[i]={cell=c.id,tile=tile.id,center=center}
    for j,d in ipairs(directions) do
      if tile.marks[j]==1 then
        local port=vertex(x+d[1],y+d[2])
        edges[#edges+1]={id=prefix.."/link/"..c.id.."/"..names[j],from=center,to=port}
      end
    end
  end
  return {vertices=vertices,edges=edges},placements
end
local function input_problem(s)
  fields(s.inputs,{problem=true,assignment=true})
  assert(next(P.plain(s.constraints))==nil,"constraint-use-explicit-problem")
  local problem=normalize(s.inputs.problem)
  if s.inputs.assignment then check_assignment(problem,s.inputs.assignment) end
  return true
end
local function instance_id(frame,step,receipt)
  return "marked-square/"..H.value("constraint/instance",{frame=frame,step_cm=step,
    problem=receipt.problem_sha256,assignment=receipt.assignment_sha256})
end
local function validate(instance)
  local e=instance.extensions.constraint
  local problem=normalize(e.input)
  local receipt=e.receipt
  assert(e.route=="bounded_constraint" and receipt.status=="complete" and receipt.algorithm==M.VERSION,
    "constraint-build-status")
  assert(receipt.route=="searched" or receipt.route=="replayed","constraint-solver-route")
  local expected=build_receipt(problem,receipt,receipt.route)
  assert(integer(receipt.nodes,0,receipt.node_limit) and (receipt.route~="replayed" or receipt.nodes==0),
    "constraint-node-receipt")
  expected.nodes,expected.status=receipt.nodes,"complete"
  expected.assignment_sha256=H.value("constraint/assignment",e.assignment)
  assert(receipt.seed==instance.provenance.seed and P.serialize(receipt)==P.serialize(expected),"constraint-receipt-digest")
  assert(type(e.step_cm)=="number" and e.step_cm>=.25 and e.step_cm<=2 and
    e.prefix==instance.id and e.prefix==instance_id(instance.frame,e.step_cm,receipt),"constraint-instance-identity")
  check_assignment(problem,e.assignment)
  local graph,placements=geometry(problem,e.assignment,instance.frame,e.step_cm,e.prefix)
  assert(P.serialize(graph)==P.serialize(instance.structures.graph)
    and P.serialize(placements)==P.serialize(e.placements),"constraint-graph-reconstruction")
  return {ok=true,checks={"exactly one allowed tile per occupied cell","matching marks on every shared edge",
    "all fixed boundary marks and holes respected","assignment digest and graph reconstruction"},solver=P.plain(receipt),
    construction={route="bounded_constraint",finite=true,occupied_cells=#problem.occupied}}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end
local function lower(x,v,style)
  assert(next(style)==nil,"constraint-style")
  local e=x.extensions.constraint
  local crop,transform=v.crop,P.plain(v.transform)
  local points={}
  for _,node in ipairs(x.structures.graph.vertices) do points[node.id]=node.point end
  local ops=P.array()
  local r=e.step_cm/2
  for _,placement in ipairs(e.placements) do
    local p=points[placement.center]
    local a,b=p[1],p[2]
    local commands={{"M",a-r,b-r},{"L",a+r,b-r},{"L",a+r,b+r},{"L",a-r,b+r},{"Z"}}
    ops[#ops+1]={op="path",semantic_ref=placement.center,commands=commands,transform=transform,
      paint={fill=placement.tile=="blank" and {.92,.93,.92} or {.81,.88,.91},stroke={.60,.67,.70},stroke_width=.012}}
  end
  for _,edge in ipairs(x.structures.graph.edges) do
    local a,b=points[edge.from],points[edge.to]
    ops[#ops+1]={op="path",semantic_ref=edge.id,commands={{"M",a[1],a[2]},{"L",b[1],b[2]}},
      transform=transform,paint={stroke={.15,.32,.48},stroke_width=.055,cap="round"}}
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,operations=ops,resources=P.array(),
    clip={bounds=P.plain(crop),protected_regions=P.plain(v.protected_regions)}}
end
function M.register(registry,clock)
  local d,r=M.definition(),routes(clock or (os and os.clock))
  registry:register(d,{validate_inputs=input_problem,generate=function(s,c)
    assert(c.frame.unit=="cm" and c.frame.dimension==2 and c.frame.handedness=="right","constraint-frame")
    local step=s.parameters.cell_size
    local request={problem=P.plain(s.inputs.problem),assignment=s.inputs.assignment and P.plain(s.inputs.assignment),
      options={seed=s.seed,node_limit=s.parameters.node_limit or 20000,deadline_ms=s.parameters.deadline_ms}}
    local built=r.construct("bounded_constraint",request,c)
    local receipt=built.receipt
    if receipt.status~="complete" then
      error({code="constraint_"..receipt.status,message="Finite marked-square completion: "..receipt.status,solver=receipt},0)
    end
    local prefix=instance_id(P.plain(c.frame),step,receipt)
    local graph,placements=geometry(built.problem,built.assignment,c.frame,step,prefix)
    c:consume("objects",#graph.vertices+#graph.edges)
    return {id=prefix,definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={graph=graph},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={constraint={route="bounded_constraint",input=request.problem,assignment=built.assignment,
        receipt=receipt,step_cm=step,prefix=prefix,placements=placements}}}
  end,validate=validate,lower=lower})
  return d
end
return M
