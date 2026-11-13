-- de Bruijn (1981), I sections 4-5: exact classification of regular pentagrid crossings.
local P=require("pattern")
local H=require("pattern_hash")
local M={VERSION="regular-pentagrid-p3-v1"}
local sqrt5=math.sqrt(5)
local phi=(1+sqrt5)/2
local c1,c2=(sqrt5-1)/4,-(sqrt5+1)/4
local s1,s2=math.sqrt(10+2*sqrt5)/4,math.sqrt(10-2*sqrt5)/4
local directions={{1,0},{c1,s1},{c2,s2},{c2,-s2},{c1,-s1}}
local sine={{0,0},{0,1},{1,0},{-1,0},{0,-1}}
local phase_profiles={
  amber={numerators={1,2,4,8,-15},denominator=31},
  indigo={numerators={-7,3,11,-4,-3},denominator=37},
}
local function integer(x) return type(x)=="number" and math.type(x)=="integer" end
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function sine_ratio(n,d)
  local a,b=sine[n%5+1],sine[d%5+1]
  assert(b[1]~=0 or b[2]~=0,"penrose-parallel-grid-families")
  if b[1]~=0 then return {a[1]*b[1],a[2]*b[1]} end
  return {(a[2]-a[1])*b[2],a[1]*b[2]}
end
local function projection_ratios(i,j,l)
  return sine_ratio(j-l,j-i),sine_ratio(l-i,j-i)
end
function M.phase(numerators,denominator)
  assert(type(numerators)=="table" and #numerators==5 and integer(denominator)
    and denominator>=1 and denominator<=257,"penrose-phase-domain")
  local sum=0
  for _,v in ipairs(numerators) do
    assert(integer(v) and math.abs(v)<=denominator*8,"penrose-phase-coordinate")
    sum=sum+v
  end
  assert(sum==0,"penrose-phase-must-sum-zero")
  local witnesses={}
  for i=1,3 do for j=i+1,4 do for l=j+1,5 do
    local a,b=projection_ratios(i,j,l)
    local u=(-a[1]*numerators[i]-b[1]*numerators[j]+numerators[l])%denominator
    local v=(-a[2]*numerators[i]-b[2]*numerators[j])%denominator
    assert(u~=0 or v~=0,"penrose-phase-not-certified-regular")
    witnesses[#witnesses+1]={families={i,j,l},residue={u,v}}
  end end end
  return {numerators=P.plain(numerators),denominator=denominator,regularity=witnesses}
end
local function sign_integer(x)
  if x<0 then return -1 elseif x>0 then return 1 else return 0 end
end
local function exact_sign(a,b)
  local x,y=2*a+b,b
  local sx,sy=sign_integer(x),sign_integer(y)
  if sx==0 then return sy elseif sy==0 or sx==sy then return sx end
  assert(math.abs(x)<=2^29 and math.abs(y)<=2^29,"penrose-algebraic-sign-budget")
  return sx*sign_integer(x*x-5*y*y)
end
local function exact_ceiling(a,b,d)
  local ceiling=math.ceil((a+b*phi)/d)
  while exact_sign(a-(ceiling-1)*d,b)<=0 do ceiling=ceiling-1 end
  while exact_sign(a-ceiling*d,b)>0 do ceiling=ceiling+1 end
  assert(exact_sign(a-ceiling*d,b)~=0,"penrose-singular-crossing")
  return ceiling
end
local function sum(k)
  local n=0
  for i=1,5 do n=n+k[i] end
  return n
end
local function project(k)
  local x,y=0,0
  for i,u in ipairs(directions) do x=x+k[i]*u[1];y=y+k[i]*u[2] end
  return {x,y}
end
local function add_lifts(k,i,j)
  local p={table.unpack(k)}
  if i then p[i]=p[i]+1 end
  if j then p[j]=p[j]+1 end
  return p
end
local function crossing(i,j,m,n,phase)
  local d,g=phase.denominator,phase.numerators
  local u,v=d*m-g[i],d*n-g[j]
  local lift={}
  for l=1,5 do
    if l==i then lift[l]=m
    elseif l==j then lift[l]=n
    else
      local a,b=projection_ratios(i,j,l)
      lift[l]=exact_ceiling(a[1]*u+b[1]*v+g[l],a[2]*u+b[2]*v,d)
    end
  end
  local delta=j-i
  local ccw_i,ccw_j=i,j
  if delta>=3 then ccw_i,ccw_j=j,i end
  local thick=delta==1 or delta==4
  local corners={lift,add_lifts(lift,ccw_i),add_lifts(lift,i,j),add_lifts(lift,ccw_j)}
  local points,indices={},{}
  local box={math.huge,math.huge,-math.huge,-math.huge}
  for a,k in ipairs(corners) do
    local p=project(k)
    local index=sum(k)
    assert(index>=1 and index<=4,"penrose-vertex-index-outside-window")
    indices[a]=index;points[a]=p
    box[1],box[2]=math.min(box[1],p[1]),math.min(box[2],p[2])
    box[3],box[4]=math.max(box[3],p[1]),math.max(box[4],p[2])
  end
  return {address={i,j,m,n},lift=lift,corners=corners,points=points,indices=indices,
    box=box,prototype=thick and "thick" or "thin",acute_at_base=thick}
end
local function lift_key(k) return table.concat(k,"/") end
local function edge_key(a,b)
  if P.byte_less(b,a) then return b.."+"..a,true end
  return a.."+"..b,false
end
local function arrow(cell,i)
  local j=i%4+1
  local a,b=cell.indices[i],cell.indices[j]
  assert(math.abs(a-b)==1,"penrose-edge-index-step")
  local green=(math.min(a,b)==1 or math.max(a,b)==4)
  local forward
  if green then forward=(a==2 and b==1) or (a==3 and b==4)
  else forward=(i%2==1)==cell.acute_at_base end
  return {class=green and "green" or "red",multiplicity=green and 2 or 1,forward=forward}
end
local function sorted_keys(t)
  local out={}
  for k in pairs(t) do out[#out+1]=k end
  table.sort(out,P.byte_less)
  return out
end
local function grow(b,h) return {b[1]-h,b[2]-h,b[3]+h,b[4]+h} end
local function intersects(a,b,eps)
  return a[1]<=b[3]+eps and a[3]+eps>=b[1] and a[2]<=b[4]+eps and a[4]+eps>=b[2]
end
local function line_ranges(box,phase)
  local shift=project(phase.numerators)
  local d=phase.denominator
  local primal={.4*(box[1]-shift[1]/d)-2,.4*(box[2]-shift[2]/d)-2,
    .4*(box[3]-shift[1]/d)+2,.4*(box[4]-shift[2]/d)+2}
  local limits={}
  for i,u in ipairs(directions) do
    local a,b=u[1]*primal[1],u[1]*primal[3]
    local c,e=u[2]*primal[2],u[2]*primal[4]
    local phase_i=phase.numerators[i]/d
    local lo=math.floor(math.min(a,b)+math.min(c,e)+phase_i)-1
    local hi=math.ceil(math.max(a,b)+math.max(c,e)+phase_i)+1
    assert(lo>=-32768 and hi<=32768,"penrose-grid-line-budget")
    limits[i]={lo,hi}
  end
  return limits
end

local function normalized_box(world,origin,step)
  local box={}
  for i=1,4 do
    box[i]=(world[i]-origin[(i-1)%2+1])/step
    assert(finite(box[i]) and math.abs(box[i])<=3000,"penrose-query-coordinate")
  end
  assert(box[1]<box[3] and box[2]<box[4] and box[3]-box[1]<=30 and box[4]-box[2]<=30,
    "penrose-query-span")
  return box
end
local function construct(request,context)
  local selected_profile=assert(phase_profiles[request.phase],"penrose-unsupported-phase")
  local phase=M.phase(selected_profile.numerators,selected_profile.denominator)
  local frame=request.frame
  local origin=frame.origin
  assert(frame.unit=="cm" and frame.dimension==2 and frame.handedness=="right","penrose-world-frame")
  local step=request.step_cm
  assert(finite(step) and step>=.15 and step<=2,"penrose-edge-length")
  local halo=request.halo
  assert(finite(halo) and halo>=2 and halo<=4,"penrose-halo")
  local query=normalized_box(request.world_query,origin,step)
  local selected_box=grow(query,halo)
  local wide_box=grow(selected_box,2.125)
  local ranges=line_ranges(wide_box,phase)
  local epsilon=math.max(1,math.abs(query[1]),math.abs(query[2]),math.abs(query[3]),math.abs(query[4]))*1e-12
  local prefix="penrose/"..H.value("penrose/fixed-pentagrid",{frame=frame,step_cm=step,phase=phase,method=M.VERSION})
  local function world(p) return {origin[1]+step*p[1],origin[2]+step*p[2]} end
  local function cell_id(c) return prefix.."/rhomb/"..table.concat(c.address,"/") end
  local function vertex_id(key) return prefix.."/v/"..key end
  local function edge_id(key) return prefix.."/e/"..key end
  local used_geometry,global_edges,selected_vertices,selected_edges={},{},{},{}
  local selected=P.array()
  local wide_count,examined=0,0
  local counts={thick=0,thin=0}
  for i=1,4 do for j=i+1,5 do
    local a,b=ranges[i],ranges[j]
    local work=(a[2]-a[1]+1)*(b[2]-b[1]+1)
    if context then context:consume("operations",work) end
    examined=examined+work
    for m=a[1],a[2] do for n=b[1],b[2] do
      local c=crossing(i,j,m,n,phase)
      if intersects(c.box,wide_box,epsilon) then
        local id=cell_id(c)
        local keep=intersects(c.box,selected_box,epsilon)
        local keys,signature={},{}
        for k,p in ipairs(c.corners) do keys[k]=lift_key(p);signature[k]=keys[k] end
        table.sort(signature,P.byte_less)
        local g=table.concat(signature,"+")
        assert(not used_geometry[g],"penrose-duplicate-rhombus")
        used_geometry[g]=true
        wide_count=wide_count+1
        local boundary=P.array()
        for k,v in ipairs(keys) do
          local w=keys[k%4+1]
          local key,reversed=edge_key(v,w)
          local a0=arrow(c,k)
          local forward=a0.forward~=reversed
          local e=global_edges[key]
          if not e then
            e={from=reversed and w or v,to=reversed and v or w,uses={},
              class=a0.class,multiplicity=a0.multiplicity,forward=forward}
            global_edges[key]=e
          else
            assert(e.class==a0.class and e.forward==forward,"penrose-arrow-seam-disagreement")
          end
          assert(#e.uses<=1 and (#e.uses==0 or e.uses[1].reversed~=reversed),"penrose-edge-incidence")
          e.uses[#e.uses+1]={cell=id,reversed=reversed,selected=keep}
          if keep then
            selected_edges[key]=true
            selected_vertices[v]={id=vertex_id(v),point=world(c.points[k]),lift=c.corners[k],index=c.indices[k]}
            boundary[k]={edge=edge_id(key),reversed=reversed,matching_class=a0.class}
          end
        end
        if keep then
          local first=(j-i)<3 and i or j
          selected[#selected+1]={id=id,prototype=c.prototype,address=c.address,base_lift=c.lift,chirality=1,boundary=boundary,
            isometry={rotation_degrees=72*(first-1),reflection=false,translation=world(c.points[1])}}
          counts[c.prototype]=counts[c.prototype]+1
        end
      end
    end end
  end end
  assert(#selected>0 and #selected<=850,"penrose-cell-budget")
  local edges,vertices=P.array(),P.array()
  local interior,cuts=0,0
  for _,key in ipairs(sorted_keys(selected_edges)) do
    local e=global_edges[key]
    assert(#e.uses==2,"penrose-insufficient-global-neighbor-halo")
    local global,visible={},{}
    for _,u in ipairs(e.uses) do
      global[#global+1]=u.cell
      if u.selected then visible[#visible+1]=u.cell end
    end
    table.sort(global,P.byte_less);table.sort(visible,P.byte_less)
    local is_interior=#visible==2
    if is_interior then interior=interior+1 else cuts=cuts+1 end
    local a,b=vertex_id(e.from),vertex_id(e.to)
    edges[#edges+1]={id=edge_id(key),from=a,to=b,owner=visible[1],role=is_interior and "interior" or "patch_boundary",
      boundary_reason=is_interior and "none" or "query_cut",global_owner=global[1],global_cells=global,
      matching={class=e.class,multiplicity=e.multiplicity,from=e.forward and a or b,to=e.forward and b or a}}
  end
  for _,key in ipairs(sorted_keys(selected_vertices)) do vertices[#vertices+1]=selected_vertices[key] end
  if context then context:consume("objects",#selected+#edges+#vertices) end
  local certificate={method=M.VERSION,source="de Bruijn 1981, I sections 2, 4, 5 and 7; II sections 9-10",
    phase=phase,frame=P.plain(frame),step_cm=step,finite=true,hierarchy="lifted grid crossing lineage",
    normalized_query=query,normalized_selection_box=selected_box,halo_edge_units=halo,line_ranges=ranges,
    candidate_crossings=examined,neighbor_patch_rhombi=wide_count,selected_counts=counts,interior_seams=interior,query_cuts=cuts,
    hypotheses={"zero-sum rational phases","certified regular pentagrid","right-handed Euclidean frame",
      "single and double arrows agree in physical direction","source coverage bound 5 in dual units"},
    checks={"exact algebraic ceiling","modular nonsingularity for all ten triples","canonical lifts and index range",
      "duplicate rhombus rejection","matching arrows and shared edges","conservative query and neighbor halo"}}
  return {prefix=prefix,tiling={cells=selected,vertices=vertices,edges=edges},certificate=certificate}
end

function M.definition()
  return P.definition({id="tiling/penrose-p3",version="1",family="regular-pentagrid-penrose",units="cm",capabilities={"tiling"},
    parameters={edge_length={type="number",minimum=.15,maximum=2,required=true},
      phase={type="string",enum={"amber","indigo"}},halo={type="number",minimum=2,maximum=4}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Regular pentagrid P3 with explicit rational phase and fixed physical frame",
      "Finite query certification and exact lift identities; no substitution hierarchy claimed",
      "Kite and dart not part of this profile"}})
end
local function providers()
  local r=require("pattern_aperiodic").route_registry()
  r.register("projection_multigrid",{construct=construct,validate=function(p)
    local counts=p.certificate.selected_counts
    return #p.tiling.cells==counts.thick+counts.thin and #p.certificate.phase.regularity==10
  end})
  return r
end
local function validate(x)
  local e=x.extensions.penrose
  assert(e.route=="projection_multigrid" and P.serialize(e.request.frame)==P.serialize(x.frame),"penrose-construction-frame")
  local r=providers()
  assert(P.serialize(e.capabilities)==P.serialize(r.capabilities()),"penrose-route-certificate")
  local actual=r.construct(e.route,P.plain(e.request))
  assert(P.serialize(actual.tiling)==P.serialize(x.structures.tiling),"penrose-lift-or-matching-reconstruction")
  assert(P.serialize(actual.certificate)==P.serialize(e.certificate),"penrose-finite-query-reconstruction")
  return {ok=true,checks=P.plain(e.certificate.checks),construction=P.plain(e.certificate)}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end

local colors={
  clean={thick={.16,.42,.54},thin={.88,.68,.36}},
  matching={thick={.92,.88,.78},thin={.80,.88,.91}},
}
local function lower(x,v,style)
  for k in pairs(style) do assert(k=="display" or k=="stroke_width" or k=="palette","penrose-unsupported-style:"..k) end
  local display=style.display or "clean"
  local fill=assert(colors[display],"penrose-unsupported-display")
  if style.palette then
    assert(style.palette=="plum","penrose-unsupported-palette")
    fill={thick={.49,.29,.47},thin={.81,.67,.69}}
  end
  local width=style.stroke_width or .012
  assert(finite(width) and width>0 and width<=.12,"penrose-stroke-width")
  local G=require("pattern_geometry")
  local m=P.plain(v.transform)
  local crop=v.crop
  local request=x.extensions.penrose.request
  local q=request.world_query
  local inverse=G.inverse(m,G.policy("cm",request.step_cm))
  for _,corner in ipairs{{crop[1],crop[2]},{crop[3],crop[2]},{crop[3],crop[4]},{crop[1],crop[4]}} do
    local p=G.transform(corner,inverse)
    assert(p[1]>=q[1]-1e-10 and p[1]<=q[3]+1e-10 and p[2]>=q[2]-1e-10 and p[2]<=q[4]+1e-10,
      "penrose-view-outside-certified-query")
  end
  local world,page,edges,ops={},{},{},{}
  local t=x.structures.tiling
  for _,a in ipairs(t.vertices) do world[a.id]=a.point;page[a.id]=G.transform(a.point,m) end
  for _,e in ipairs(t.edges) do edges[e.id]=e end
  local function visible(box,pad) return intersects(box,crop,pad) end
  for _,cell in ipairs(t.cells) do
    local cmd={}
    local box={math.huge,math.huge,-math.huge,-math.huge}
    for i,use in ipairs(cell.boundary) do
      local e=edges[use.edge]
      local id=use.reversed and e.to or e.from
      local p,a=world[id],page[id]
      cmd[i]={i==1 and "M" or "L",p[1],p[2]}
      box[1],box[2]=math.min(box[1],a[1]),math.min(box[2],a[2])
      box[3],box[4]=math.max(box[3],a[1]),math.max(box[4],a[2])
    end
    if visible(box,0) then
      cmd[#cmd+1]={"Z"}
      ops[#ops+1]={op="path",semantic_ref=cell.id,commands=cmd,transform=m,paint={fill=fill[cell.prototype]}}
    end
  end
  local scale=math.sqrt(m[1]^2+m[2]^2+m[3]^2+m[4]^2)
  local pad=(width+(display=="matching" and request.step_cm*.15 or 0))*scale
  for _,e in ipairs(t.edges) do
    local a,b=page[e.from],page[e.to]
    if visible({math.min(a[1],b[1]),math.min(a[2],b[2]),math.max(a[1],b[1]),math.max(a[2],b[2])},pad) then
      local p,r=world[e.from],world[e.to]
      local mark=e.matching
      local stroke=display=="clean" and {.06,.15,.22} or
        (mark.class=="red" and {.69,.22,.25} or {.14,.38,.28})
      ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",p[1],p[2]},{"L",r[1],r[2]}},
        transform=m,paint={stroke=stroke,stroke_width=width}}
      if display=="matching" then
        p,r=world[mark.from],world[mark.to]
        local dx,dy=r[1]-p[1],r[2]-p[2]
        local fractions=mark.multiplicity==1 and {.54} or {.44,.61}
        for _,f in ipairs(fractions) do
          local u,w=p[1]+f*dx,p[2]+f*dy
          local a0,b0=u-.13*dx,w-.13*dy
          local nx,ny=-.085*dy,.085*dx
          ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",a0+nx,b0+ny},{"L",u,w},{"L",a0-nx,b0-ny}},
            transform=m,paint={stroke=stroke,stroke_width=width}}
        end
      end
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end

function M.register(registry)
  local d=M.definition()
  local r=providers()
  registry:register(d,{generate=function(s,context)
    local a=s.parameters
    local request={phase=a.phase or "amber",step_cm=a.edge_length,halo=a.halo or 2,
      frame=P.plain(context.frame),world_query=P.plain(s.document.bounds)}
    local p=r.construct("projection_multigrid",request,context)
    return {id=p.prefix.."/query/"..H.value("penrose/finite-query",request),definition_ref={id=d.id,version=d.version},
      frame=P.plain(context.frame),structures={tiling=p.tiling},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={penrose={route="projection_multigrid",request=request,certificate=p.certificate,capabilities=P.plain(r.capabilities())}}}
  end,validate=validate,lower=lower})
  return d
end
return M
