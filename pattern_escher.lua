local P,G,H=require("pattern"),require("pattern_geometry"),require("pattern_hash")
local Metric=require("pattern_escher_metric")
local Periodic=require("pattern_escher_periodic")
local P3=require("pattern_escher_p3")
local Penrose=require("pattern_penrose")
local M={VERSION="escher-boundary-coupling-v1"}
-- Turning-function diagnostics use the existing 1e-12 numerical policy.
-- The witness, source geometry and combinatorial certificates remain exact.
local function metric_close(recorded,computed)
  return type(recorded)=="number" and recorded>=0 and recorded<math.huge
    and math.abs(recorded-computed)<=1e-12*math.max(1,math.abs(computed))
end
local function metric_errors(recorded,computed)
  if type(recorded)~="table" or #recorded~=#computed then return false end
  for key in pairs(recorded) do
    if type(key)~="number" or key%1~=0 or key<1 or key>#computed then return false end
  end
  for i,value in ipairs(computed) do
    if not metric_close(recorded[i],value) then return false end
  end
  return true
end
local function domain(request)
  if request.profile=="penrose" then return P3.domain() end
  return Periodic.domain(request.profile=="split")
end
local function shapes(request,values)
  if request.profile=="penrose" then return P3.shapes(values) end
  return Periodic.shapes(values,request)
end
local function goal_records(targets)
  local out={}
  for i,polygon in ipairs(targets) do out[i]=Metric.turning(Metric.polygon(polygon)) end
  return out
end
local function target_list(input,count)
  assert(type(input)=="table" and #input==count,"escher-target-count")
  for k in pairs(input) do
    assert(type(k)=="number" and k%1==0 and k>=1 and k<=count,"escher-target-array")
  end
  local targets=P.array()
  for i=1,count do targets[i]=P.plain(Metric.polygon(input[i])) end
  return targets
end
local function witness(values,bounds)
  assert(type(values)=="table" and #values==#bounds,"escher-witness-size")
  for k in pairs(values) do
    assert(type(k)=="number" and k%1==0 and k>=1 and k<=#bounds,"escher-witness-array")
  end
  for i,b in ipairs(bounds) do
    local v=values[i]
    assert(type(v)=="number" and v%1==0 and v>=b[1] and v<=b[2],"escher-witness-outside-domain")
  end
  return P.plain(values)
end
local function request_from(s,c)
  local a=s.parameters
  if a.profile=="penrose" then assert(a.aspect==nil and a.shear==nil,"escher-p3-scaffold-metric-fixed")
  else assert(a.phase==nil,"escher-phase-requires-penrose") end
  local request={profile=a.profile,step_cm=a.edge_length,frame=P.plain(c.frame),query=P.plain(s.document.bounds),
    phase=a.profile=="penrose" and (a.phase or "amber") or nil,
    aspect=a.profile~="penrose" and (a.aspect or 1) or nil,
    shear=a.profile~="penrose" and (a.shear or 0) or nil}
  if a.profile=="penrose" then
    for i,v in ipairs(request.query) do
      assert(math.abs((v-request.frame.origin[(i-1)%2+1])/request.step_cm)<=32,"escher-p3-query-horizon")
    end
  end
  return request
end
local function evaluate(request,targets,context)
  local goals=goal_records(targets)
  local initial=domain(request)
  local base=request.profile=="penrose" and P3.baseline() or shapes(request,initial)
  local baseline,baseline_errors=Metric.objective(base,goals)
  local function score(values)
    local p=shapes(request,values)
    if p then return Metric.objective(p,goals,context) end
  end
  return baseline,baseline_errors,score
end
local function stop(status,receipt)
  receipt.status=status
  error({code="escher_"..status,message="Escherization: "..status,solver=receipt},0)
end
local function solve(request,s,targets,c)
  local baseline,baseline_errors,score=evaluate(request,targets,c)
  local initial,bounds=domain(request)
  local steps=s.parameters.steps or 180
  local receipt={algorithm=Metric.VERSION,seed=s.seed,budget=steps,baseline=baseline,
    baseline_errors=baseline_errors,targets_sha256=H.value("escher/targets",targets),
    objective=#targets==1 and "turning-L2" or "max-of-two-turning-L2",
    target_assignment=request.profile=="penrose" and {"thick","thin"} or
      (request.profile=="split" and {"west","east"} or {"mono"})}
  local values
  if s.inputs.witness then
    values=witness(s.inputs.witness,bounds)
    receipt.route="replayed"
    receipt.evaluations=1
    receipt.score,receipt.errors=score(values)
    if not receipt.score then stop("inadmissible_witness",receipt) end
  else
    receipt.route="annealed"
    if steps==0 then stop("limited",receipt) end
    local result=Metric.anneal(initial,bounds,steps,c:stream("shape-anneal",request.profile),score)
    values=result.values
    receipt.evaluations=steps+1
    receipt.score,receipt.errors=result.score,result.errors
    receipt.accepted,receipt.invalid_proposals,receipt.improvements=result.accepted,result.invalid_proposals,result.improvements
    receipt.temperature=result.temperature
  end
  if receipt.score>=baseline-1e-8 then stop("no_improvement",receipt) end
  receipt.status="improved"
  receipt.witness_sha256=H.value("escher/witness",values)
  return values,receipt
end
local function base_penrose(reg,d,request,seed,budget,c)
  local s={id="escher/penrose-source",definition_ref={id=d.id,version=d.version},
    seed=seed,parameters={edge_length=request.step_cm,phase=request.phase},inputs={},style={},constraints={},
    budget=P.plain(budget),document={unit="cm",bounds=P.plain(request.query),protected_regions=P.array()}}
  local r,e=reg:generate(d.id,s,c)
  assert(r,e and P.serialize(e))
  return r.instance
end
local function prefix(request,values)
  local key=P.plain(request)
  key.query=nil
  return "escher/"..H.value("escher/geometry",{method=M.VERSION,request=key,values=values})
end
local function build(request,values,source,c)
  local key=prefix(request,values)
  if request.profile=="penrose" then return P3.patch(source,values,request.query,key,c) end
  return Periodic.patch(request,values,key,c)
end
function M.definition()
  return P.definition({id="tiling/escherization",version="1",family="boundary-coupled-escherization",
    units="cm",capabilities={"tiling"},parameters={
      profile={type="string",enum={"periodic","split","penrose"},required=true},
      edge_length={type="number",minimum=.2,maximum=2,required=true},
      aspect={type="number",minimum=.65,maximum=1.7},shear={type="number",minimum=-.45,maximum=.45},
      phase={type="string",enum={"amber","indigo"}},steps={type="integer",minimum=0,maximum=480}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Bounded IH41 and split-IH41 translation charts",
      "Four active source quasivertex controls and paired fundamental edges for Penrose P3",
      "Normalized turning distance and deterministic bounded annealing for simple CCW targets",
      "Retained source scaffold and explicit finite deformation validation"}})
end
local function check_inputs(s)
  for k in pairs(s.inputs) do assert(k=="targets" or k=="witness","escher-input:"..k) end
  assert(next(P.plain(s.constraints))==nil,"escher-unsupported-constraints")
  target_list(s.inputs.targets,s.parameters.profile=="periodic" and 1 or 2)
  return true
end
local function validate(x)
  local e=x.extensions.escher
  local request=e.request
  assert(P.serialize(x.frame)==P.serialize(request.frame),"escher-frame")
  local _,bounds=domain(request)
  local values=witness(e.values,bounds)
  local targets=target_list(e.targets,request.profile=="periodic" and 1 or 2)
  local baseline,baseline_errors,score=evaluate(request,targets)
  local best,errors=score(values)
  assert(best and best<baseline-1e-8,"escher-witness-does-not-improve")
  local s=e.solver
  assert(s.algorithm==Metric.VERSION and s.status=="improved" and s.seed==x.provenance.seed
    and s.targets_sha256==H.value("escher/targets",targets) and s.witness_sha256==H.value("escher/witness",values),
    "escher-solver-provenance")
  assert(s.route=="annealed" or s.route=="replayed","escher-solver-route")
  assert(metric_close(s.baseline,baseline) and metric_close(s.score,best) and metric_errors(s.errors,errors)
    and metric_errors(s.baseline_errors,baseline_errors),"escher-objective-reconstruction")
  if request.profile=="penrose" then
    local q=e.scaffold.extensions.penrose.request
    assert(P.serialize(e.scaffold.frame)==P.serialize(x.frame) and q.step_cm==request.step_cm
      and q.phase==request.phase and P.serialize(q.world_query)==P.serialize(request.query),"escher-source-scaffold")
    Penrose.validate(e.scaffold)
  else assert(e.scaffold==nil,"escher-unexpected-scaffold") end
  local tiling,proof=build(request,values,e.scaffold)
  assert(P.serialize(tiling)==P.serialize(x.structures.tiling) and P.serialize(proof)==P.serialize(e.certificate),
    "escher-patch-reconstruction")
  return {ok=true,solver=P.plain(s),construction=P.plain(proof),
    checks={"simple positive prototile contours and an improving witness",
      "matched directed edge classes and reconstructed shared paths",
      "bounded source chart and finite query coverage"}}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end
local function intersects(points,crop,pad)
  local l,b,r,t=math.huge,math.huge,-math.huge,-math.huge
  for _,p in ipairs(points) do l,b,r,t=math.min(l,p[1]),math.min(b,p[2]),math.max(r,p[1]),math.max(t,p[2]) end
  return l<=crop[3]+pad and b<=crop[4]+pad and r>=crop[1]-pad and t>=crop[2]-pad
end
local function indexed(items)
  local map={}
  for _,v in ipairs(items) do map[v.id]=v end
  return map
end
local function points_of(cell,edges)
  local out={}
  for _,use in ipairs(cell.boundary) do
    local path=edges[use.edge].path
    for i=1,#path-1 do out[#out+1]=path[use.reversed and #path-i+1 or i] end
  end
  return out
end
local colors={mono={.31,.59,.64},west={.21,.42,.58},east={.82,.63,.37},
  thick={.28,.54,.51},thin={.86,.65,.39}}
local function lower(x,v,style)
  for k in pairs(style) do assert(k=="display","escher-style:"..k) end
  local display=style.display or "design"
  assert(display=="design" or display=="scaffold","escher-display")
  local e=x.extensions.escher
  local transform=P.plain(v.transform)
  local crop=v.crop
  local inverse=G.inverse(transform,G.policy("cm",e.request.step_cm))
  local q=e.request.query
  for _,corner in ipairs{{crop[1],crop[2]},{crop[3],crop[2]},{crop[3],crop[4]},{crop[1],crop[4]}} do
    local p=G.transform(corner,inverse)
    assert(p[1]>=q[1]-1e-10 and p[2]>=q[2]-1e-10 and p[1]<=q[3]+1e-10 and p[2]<=q[4]+1e-10,
      "escher-view-outside-certified-query")
  end
  local tiling=x.structures.tiling
  local edges=indexed(tiling.edges)
  local source_cells,source_edges,source_vertices
  if e.scaffold then
    local s=e.scaffold.structures.tiling
    source_cells,source_edges,source_vertices=indexed(s.cells),indexed(s.edges),indexed(s.vertices)
  end
  local function scaffold_points(cell)
    if source_cells then
      local out={}
      for i,use in ipairs(source_cells[cell.source_ref].boundary) do
        local edge=source_edges[use.edge]
        out[i]=source_vertices[use.reversed and edge.to or edge.from].point
      end
      return out
    end
    local i,j=table.unpack(cell.source_slot)
    local left=cell.prototype=="east" and i+.5 or i
    local right=cell.prototype=="west" and i+.5 or i+1
    local points={}
    for n,p in ipairs{{left,j},{right,j},{right,j+1},{left,j+1}} do
      points[n]={x.frame.origin[1]+e.request.step_cm*(p[1]+e.request.shear*p[2]),
        x.frame.origin[2]+e.request.step_cm*e.request.aspect*p[2]}
    end
    return points
  end
  local ops=P.array()
  local scale=math.sqrt(transform[1]^2+transform[2]^2+transform[3]^2+transform[4]^2)
  local function path(ref,points,paint,closed)
    local commands,projected={},{}
    for i,p in ipairs(points) do
      commands[i]={i==1 and "M" or "L",p[1],p[2]}
      projected[i]=G.transform(p,transform)
    end
    if not intersects(projected,crop,(paint.stroke_width or 0)*scale) then return end
    if closed then commands[#commands+1]={"Z"} end
    ops[#ops+1]={op="path",semantic_ref=ref,commands=commands,transform=transform,paint=paint}
  end
  if display=="design" then
    for _,c in ipairs(tiling.cells) do path(c.id,points_of(c,edges),{fill=colors[c.prototype]},true) end
    for _,edge in ipairs(tiling.edges) do path(edge.id,edge.path,{stroke={.10,.21,.27},stroke_width=.014},false) end
  else
    for _,c in ipairs(tiling.cells) do
      path(c.id,scaffold_points(c),{fill=colors[c.prototype],stroke={.10,.21,.27},stroke_width=.014},true)
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,operations=ops,resources=P.array(),
    clip={bounds=P.plain(crop),protected_regions=P.plain(v.protected_regions)}}
end
function M.register(registry)
  local d=M.definition()
  local base=require("pattern_registry").new()
  local pd=Penrose.register(base)
  registry:register(d,{validate_inputs=check_inputs,generate=function(s,c)
    assert(c.frame.unit=="cm" and c.frame.dimension==2 and c.frame.handedness=="right","escher-frame")
    local request=request_from(s,c)
    local targets=target_list(s.inputs.targets,request.profile=="periodic" and 1 or 2)
    local values,solver=solve(request,s,targets,c)
    local source
    if request.profile=="penrose" then source=base_penrose(base,pd,request,s.seed,s.budget,c) end
    local tiling,certificate=build(request,values,source,c)
    return {id=prefix(request,values).."/query/"..H.value("escher/query",request.query),
      definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={tiling=tiling},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={escher={request=request,targets=targets,values=values,solver=solver,certificate=certificate,
        scaffold=source and P.plain(source) or nil}}}
  end,validate=validate,lower=lower})
  return d
end
return M
