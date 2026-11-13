local P, H = require("pattern"), require("pattern_hash")
local G = require("pattern_gothic_geometry")
local M = {VERSION="compass-biarc-network-v1"}
local abs, epsilon = math.abs, 1e-8

function M.definition()
  return P.definition({id="gothic/spatial-ogee", version="1", family="gothic-microarchitecture",
    units="cm", capabilities={"curve3d"},
    parameters={tolerance={type="number",minimum=.001,maximum=.05}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Circular compass arcs on monotone straightedge charts",
      "Side biarcs use a true replica crossing and vertical end tangents",
      "Orthographic wire views without surface occlusion"}})
end

local function number(n)
  assert(type(n)=="number" and abs(n)<=100, "gothic-bounded-coordinate")
  return n
end

local function input(s)
  local q = P.plain(s.inputs)
  assert(type(q.units)=="table" and #q.units>=1 and #q.units<=8, "gothic-unit-count")
  assert(not next(P.plain(s.constraints)), "gothic-constraints-in-construction-input")
  return q.units, s.parameters.tolerance or .004
end

local function construct(spec, units, vertices)
  local id = "unit/" .. (#units + 1)
  local radius, start, finish = number(spec.radius), number(spec.start), number(spec.finish)
  assert(radius>0 and -radius<start and start<finish and finish<radius, "gothic-top-chart")
  local circle = {center={0,0}, radius=radius, branch=1}
  local start_y = G.top(circle, start)
  local origin, anchor = {0,0,0}, nil
  if spec.parent then
    local parent = assert(units[spec.parent], "gothic-parent-must-precede-child")
    local replica = assert(parent.replicas[spec.parent_replica or 1], "gothic-parent-replica")
    anchor = replica.finish_id
    origin = vertices[anchor]
  else
    assert(type(spec.origin)=="table" and #spec.origin==2, "gothic-ground-origin")
    origin = {number(spec.origin[1]),number(spec.origin[2]),0}
  end
  local ox, oy = origin[1]-start, origin[2]-start_y
  local replicas = P.array({{x=ox,y=oy,sx=1,sy=1}})
  assert(type(spec.replicas)=="table" and #spec.replicas>=1 and #spec.replicas<=4, "gothic-replica-count")
  for _,r in ipairs(spec.replicas) do
    assert(type(r)=="table" and #r==4 and abs(number(r[3]))==1 and abs(number(r[4]))==1,
      "gothic-planar-isometry")
    replicas[#replicas+1]={x=ox+number(r[1]),y=oy+number(r[2]),sx=r[3],sy=r[4]}
  end
  local unit={id=id, origin=origin, circle=circle, start=start, finish=finish, replicas=replicas,
    construction={
      {id=id.."/center",op="compass-center",point={0,0}},
      {id=id.."/circle",op="compass-circle",dependencies={id.."/center"},radius=radius},
      {id=id.."/start-line",op="straightedge-line",x=start},
      {id=id.."/finish-line",op="straightedge-line",x=finish},
      {id=id.."/start",op="circle-line-intersection",dependencies={id.."/circle",id.."/start-line"},
        branch=1,point={start,start_y},ground_mark=not anchor,support=anchor},
      {id=id.."/finish",op="circle-line-intersection",dependencies={id.."/circle",id.."/finish-line"},
        branch=1,point={finish,G.top(circle,finish)}}},
    crossings=P.array(), support=anchor}
  local best, score
  for i=1,#replicas do
    for j=i+1,#replicas do
      for _,x in ipairs(G.crossings(unit,replicas[i],replicas[j])) do
        x.first,x.second=i,j
        x.id=id.."/crossing/"..(#unit.crossings+1)
        unit.crossings[#unit.crossings+1]=x
        if i==1 and x.joined and x.a>start+epsilon and x.a<finish-epsilon then
          local distance=abs(x.a-(start+finish)/2)
          if not score or distance<score-epsilon then best,score=x,distance end
        end
      end
    end
  end
  assert(best, "gothic-missing-interior-primary-replica-crossing")
  unit.primary=best.id
  unit.side=G.side(finish-start,number(spec.height),best.a-start)
  return unit
end

local function generate(d,s,c)
  local specs,tolerance=input(s)
  local units,curves,points=P.array(),P.array(),P.array()
  local vertices={}
  local function vertex(id,point)
    if not vertices[id] then
      vertices[id]=point
      points[#points+1]={id=id,point=point}
    else
      for k=1,3 do assert(abs(vertices[id][k]-point[k])<epsilon, "gothic-junction-position") end
    end
  end
  for _,spec in ipairs(specs) do
    local unit=construct(spec,units,vertices)
    units[#units+1]=unit
    for _,x in ipairs(unit.crossings) do
      x.first_height=unit.origin[3]+G.height(unit.side,x.a-unit.start)
      x.second_height=unit.origin[3]+G.height(unit.side,x.b-unit.start)
      assert(x.joined==(abs(x.first_height-x.second_height)<epsilon), "gothic-crossing-height")
    end
    for i,r in ipairs(unit.replicas) do
      local id=unit.id.."/curve/"..i
      local by_x={[unit.start]=(i==1 and unit.support) or id.."/a",[unit.finish]=id.."/b"}
      local knots={unit.start,unit.start+unit.side.join[1],unit.finish}
      for _,x in ipairs(unit.crossings) do
        local t=i==x.first and x.a or i==x.second and x.b or nil
        if t then
          if x.joined then
            assert(not by_x[t], "gothic-ambiguous-multiple-or-endpoint-junction")
            by_x[t]=x.id
          end
          knots[#knots+1]=t
        end
      end
      table.sort(knots)
      local distinct={}
      for _,x in ipairs(knots) do
        if #distinct==0 or x-distinct[#distinct]>epsilon then
          distinct[#distinct+1]=x
        elseif by_x[x] then
          distinct[#distinct]=x
        end
      end
      local samples=P.array()
      for j,x in ipairs(G.sample(unit,distinct,tolerance,c)) do
        local key=by_x[x] or id.."/sample/"..j
        vertex(key,G.point(unit,r,x))
        samples[j]={x=x,vertex=key}
      end
      r.finish_id=id.."/b"
      curves[#curves+1]={id=id,from=samples[1].vertex,to=samples[#samples].vertex,
        unit=unit.id,replica=i,samples=samples}
    end
  end
  return {id="gothic/"..H.value("gothic/spatial-input",{specs=specs,tolerance=tolerance}),
    definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),
    structures={curve3d={vertices=points,curves=curves}},
    provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
    extensions={gothic_spatial={units=units,chord_tolerance_cm=tolerance}}}
end

local function validate(x)
  local points={}
  for _,v in ipairs(x.structures.curve3d.vertices) do points[v.id]=v.point end
  local units={}
  for _,u in ipairs(x.extensions.gothic_spatial.units) do
    units[u.id]=u
    local a,b,j=u.side.lower,u.side.upper,u.side.join
    local ax,ay=j[1]-a.center[1],j[2]-a.center[2]
    local bx,by=j[1]-b.center[1],j[2]-b.center[2]
    assert(abs(ax^2+ay^2-a.radius^2)<epsilon and abs(bx^2+by^2-b.radius^2)<epsilon
      and abs(ax*by-ay*bx)<epsilon and ax*bx+ay*by<0 and a.curvature==-b.curvature, "gothic-biarc-certificate")
  end
  for _,curve in ipairs(x.structures.curve3d.curves) do
    local u=units[curve.unit]
    local previous=-math.huge
    for _,sample in ipairs(curve.samples) do
      local p=G.point(u,u.replicas[curve.replica],sample.x)
      for k=1,3 do assert(abs(p[k]-points[sample.vertex][k])<epsilon, "gothic-curve-sample") end
      assert(sample.x>previous, "gothic-curve-sample-order")
      previous=sample.x
    end
  end
  return {ok=true,checks={"Shared spatial junctions and nested support",
    "Opposite signed curvature with common tangent",
    "Ordered spatial samples reconstructed from analytic curves"}}
end

local function camera(matrix)
  for i=0,2 do
    for j=i,2 do
      local dot=0
      for k=1,3 do dot=dot+matrix[4*i+k]*matrix[4*j+k] end
      assert(abs(dot-(i==j and 1 or 0))<epsilon, "gothic-orthonormal-camera")
    end
  end
  assert(matrix[13]==0 and matrix[14]==0 and matrix[15]==0 and matrix[16]==1, "gothic-affine-camera")
end

local function project(m,p)
  local out={}
  for i=0,2 do out[i+1]=m[4*i+1]*p[1]+m[4*i+2]*p[2]+m[4*i+3]*p[3]+m[4*i+4] end
  return out
end

local function lower(x,v,style)
  local m=v.projection.matrix
  camera(m)
  local points={}
  for _,p in ipairs(x.structures.curve3d.vertices) do points[p.id]=project(m,p.point) end
  local paths,ops={},P.array()
  local depth_sorted=v.projection.depth_policy=="depth_sorted"
  for _,c in ipairs(x.structures.curve3d.curves) do
    local a=points[c.from]
    local commands=P.array({{"M",a[1],a[2]}})
    for i=2,#c.samples do
      local b=points[c.samples[i].vertex]
      if depth_sorted then
        paths[#paths+1]={id=c.id,index=i,depth=(a[3]+b[3])/2,
          commands={{"M",a[1],a[2]},{"L",b[1],b[2]}}}
      else
        commands[#commands+1]={"L",b[1],b[2]}
      end
      a=b
    end
    if not depth_sorted then paths[#paths+1]={id=c.id,commands=commands} end
  end
  if depth_sorted then
    table.sort(paths,function(a,b)
      local da,db=math.floor(a.depth*1e8+.5),math.floor(b.depth*1e8+.5)
      if da~=db then return da<db end
      if a.id~=b.id then return a.id<b.id end
      return a.index<b.index
    end)
  end
  local colors={{.10,.24,.34},{.60,.31,.16},{.28,.44,.34}}
  for _,p in ipairs(paths) do
    local index=tonumber(p.id:match("^unit/(%d+)/"))
    ops[#ops+1]={op="path",semantic_ref=p.id,commands=p.commands,transform=P.plain(v.transform),
      paint={stroke=P.plain(style.stroke or colors[(index-1)%#colors+1]),
        stroke_width=style.stroke_width or .018,cap="round",join="round"}}
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    operations=ops,resources=P.array(),clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)}}
end

function M.export(x)
  return P.serialize({schema="florilegium-curve-network@1",frame=x.frame,network=x.structures.curve3d,
    construction=x.extensions.gothic_spatial,provenance=x.provenance})
end

function M.register(reg)
  local d=M.definition()
  reg:register(d,{validate_inputs=function(s) input(s);return true end,
    generate=function(s,c) return generate(d,s,c) end,validate=validate,lower=lower})
  return d
end

return M
