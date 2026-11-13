-- Beenker (1982), §§2.2–2.3 and 5.1–5.3. Use integer lifts and exact
-- Q(sqrt(2)) line decisions before calculating any drawing coordinates.
local P,H,G=require("pattern"),require("pattern_hash"),require("pattern_geometry")
local M={VERSION="beenker-tetragrid-v1"}
local sqrt2=math.sqrt(2)
local half=sqrt2/2
local directions={{1,0},{half,half},{0,1},{-half,half}}
local profiles={
  offset={numerators={1,2,3,4},denominator=17,center={0,0,0,0}},
  centered={numerators={1,1,1,1},denominator=2,center={1,1,1,1}},
  ["zero-plus"]={numerators={0,0,0,0},denominator=1,center={0,0,0,0},direction={1,2,3,4}},
  ["zero-minus"]={numerators={0,0,0,0},denominator=1,center={0,0,0,0},direction={-1,-2,-3,-4}},
}
local function finite(x) return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function sign(x) return x<0 and -1 or x>0 and 1 or 0 end
local function algebraic_sign(a,b)
  local sa,sb=sign(a),sign(b)
  if sa==0 then return sb end
  if sb==0 or sa==sb then return sa end
  assert(math.abs(a)<2^29 and math.abs(b)<2^29,"beenker-algebraic-sign-budget")
  return sa*sign(a*a-2*b*b)
end

-- Twice the sine ratio, represented as a+b*sqrt(2).
local function sine_ratio(n,d)
  if n==0 then return 0,0 end
  local side=sign(n)*sign(d)
  if (math.abs(n)==2)==(math.abs(d)==2) then return 2*side,0 end
  return 0,side*(math.abs(n)==2 and 2 or 1)
end
local function coefficients(i,j,k)
  local a,b=sine_ratio(j-k,j-i)
  local c,d=sine_ratio(k-i,j-i)
  return a,b,c,d
end
local function residual(i,j,k,values)
  local a,b,c,d=coefficients(i,j,k)
  return 2*values[k]-a*values[i]-c*values[j],-b*values[i]-d*values[j]
end
local function phase_record(name)
  local phase=P.plain(assert(profiles[name],"beenker-phase"))
  phase.name=name
  phase.tie_policy=phase.direction and "coherent-positive-infinitesimal" or "regular-no-ties"
  phase.regularity=P.array()
  -- Each relation has exactly one grid index on the irrational side.
  -- A rational phase at that index must be integral for a triple tie.
  for _,triple in ipairs{{1,2,3,2},{1,2,4,1},{1,3,4,4},{2,3,4,3}} do
    local i,j,k,l=table.unpack(triple)
    local witness={families={i,j,k},irrational_side=l}
    if phase.direction then
      local a,b=residual(i,j,k,phase.direction)
      assert(algebraic_sign(a,b)~=0,"beenker-degenerate-perturbation")
      witness.perturbation={a,b}
    else
      witness.residue=phase.numerators[l]%phase.denominator
      assert(witness.residue~=0,"beenker-phase-not-regular")
    end
    phase.regularity[#phase.regularity+1]=witness
  end
  return phase
end

local function ceiling(a,b,d,phase,i,j,k)
  -- The float estimate only starts the search. Exact comparisons make
  -- the decision, including equality at a singular line.
  local c=math.ceil((a+b*sqrt2)/d)
  while algebraic_sign(a-(c-1)*d,b)<=0 do c=c-1 end
  while algebraic_sign(a-c*d,b)>0 do c=c+1 end
  if algebraic_sign(a-c*d,b)~=0 then return c end
  assert(phase.direction,"beenker-unexpected-tie")
  local u,v=residual(i,j,k,phase.direction)
  local side=algebraic_sign(u,v)
  assert(side~=0,"beenker-unresolved-tie")
  return c+(side>0 and 1 or 0),{family=k,line=c,residual={u,v},side=side}
end
local function shift(k,i,j)
  local out={table.unpack(k)}
  if i then out[i]=out[i]+1 end
  if j then out[j]=out[j]+1 end
  return out
end
local function exact_points(k,center)
  local a,b,c,d=k[1]-center[1],k[2]-center[2],k[3]-center[3],k[4]-center[4]
  return {{2*a,b-d},{2*c,b+d}},{{2*a,d-b},{-2*c,b+d}}
end
local function point(exact)
  return {(exact[1][1]+exact[1][2]*sqrt2)/2,(exact[2][1]+exact[2][2]*sqrt2)/2}
end
local function bounds(points)
  local x0,y0,x1,y1=math.huge,math.huge,-math.huge,-math.huge
  for _,p in ipairs(points) do
    x0,y0,x1,y1=math.min(x0,p[1]),math.min(y0,p[2]),math.max(x1,p[1]),math.max(y1,p[2])
  end
  return {x0,y0,x1,y1}
end
local function crossing(i,j,m,n,phase)
  local d,g=phase.denominator,phase.numerators
  local u,v=m*d-g[i],n*d-g[j]
  local base={[i]=m,[j]=n}
  local ties=P.array()
  for k=1,4 do
    if k~=i and k~=j then
      local a,b,c,e=coefficients(i,j,k)
      local lift,tie=ceiling(a*u+c*v+2*g[k],b*u+e*v,2*d,phase,i,j,k)
      base[k]=lift
      if tie then ties[#ties+1]=tie end
    end
  end
  local corners={base,shift(base,i),shift(base,i,j),shift(base,j)}
  local points={}
  for a,k in ipairs(corners) do points[a]=point(exact_points(k,phase.center)) end
  return {address={i,j,m,n},corners=corners,points=points,box=bounds(points),ties=ties,
    prototype=j-i==2 and "square" or "rhombus"}
end
local function key(k) return table.concat(k,"/") end
local function sorted_keys(t)
  local list={}
  for k in pairs(t) do list[#list+1]=k end
  table.sort(list,P.byte_less)
  return list
end
local function grow(b,h) return {b[1]-h,b[2]-h,b[3]+h,b[4]+h} end
local function intersects(a,b,e)
  return a[1]<=b[3]+e and a[3]+e>=b[1] and a[2]<=b[4]+e and a[4]+e>=b[2]
end
local function ranges(box,phase)
  -- f(z)=2z+sum((gamma+error-center)*u). With these profiles, each
  -- summand has norm <=1.5, so half the displacement is <=3.
  -- One extra unit on each side covers the integer line end bounds.
  local primal={box[1]/2-3,box[2]/2-3,box[3]/2+3,box[4]/2+3}
  local out={}
  for i,u in ipairs(directions) do
    local a,b=u[1]*primal[1],u[1]*primal[3]
    local c,d=u[2]*primal[2],u[2]*primal[4]
    local g=phase.numerators[i]/phase.denominator
    out[i]={math.floor(math.min(a,b)+math.min(c,d)+g)-1,
      math.ceil(math.max(a,b)+math.max(c,d)+g)+1}
  end
  return out
end
local function construct(request,context)
  local frame,step=request.frame,request.step_cm
  assert(frame.unit=="cm" and frame.dimension==2 and frame.handedness=="right","beenker-frame")
  assert(finite(step) and step>=.2 and step<=2,"beenker-edge-length")
  local origin=G.point(frame.origin)
  local query={}
  for i,v in ipairs(request.world_query) do
    query[i]=(v-origin[(i-1)%2+1])/step
    assert(finite(query[i]) and math.abs(query[i])<=64,"beenker-query-horizon")
  end
  assert(#query==4 and query[1]<query[3] and query[2]<query[4],"beenker-empty-query")
  local phase=phase_record(request.phase)
  local selected_box=grow(query,2)
  local wide_box=grow(selected_box,2)
  local limits=ranges(wide_box,phase)
  local epsilon=1e-10
  local prefix="beenker/"..H.value("beenker/frame",{frame=frame,step_cm=step,phase=phase,method=M.VERSION})
  local function vertex_id(k) return prefix.."/v/"..k end
  local function edge_id(k) return prefix.."/e/"..k end
  local function world(p) return {origin[1]+step*p[1],origin[2]+step*p[2]} end
  local cells,edges,vertices=P.array(),P.array(),P.array()
  local used,all_edges,visible_edges,visible_vertices={},{},{},{}
  local examined,wide_count,tie_count,positive_ties,negative_ties=0,0,0,0,0
  local counts={square=0,rhombus=0}
  for i=1,3 do for j=i+1,4 do
    local a,b=limits[i],limits[j]
    local work=(a[2]-a[1]+1)*(b[2]-b[1]+1)
    if context then context:consume("operations",work) end
    examined=examined+work
    for m=a[1],a[2] do for n=b[1],b[2] do
      local c=crossing(i,j,m,n,phase)
      if intersects(c.box,wide_box,epsilon) then
        wide_count=wide_count+1
        local id=prefix.."/cell/"..key(c.address)
        local keep=intersects(c.box,selected_box,epsilon)
        local boundary=P.array()
        local keys={}
        for k,lift in ipairs(c.corners) do keys[k]=key(lift) end
        local signature={table.unpack(keys)}
        table.sort(signature,P.byte_less)
        local geometry=table.concat(signature,"+")
        assert(not used[geometry],"beenker-duplicate-tile")
        used[geometry]=true
        for k,from in ipairs(keys) do
          local to=keys[k%4+1]
          local reversed=P.byte_less(to,from)
          local v,w=from,to
          if reversed then v,w=to,from end
          local ekey=v.."+"..w
          local edge=all_edges[ekey]
          if not edge then edge={from=v,to=w,uses={}};all_edges[ekey]=edge end
          assert(#edge.uses<2 and (#edge.uses==0 or edge.uses[1].reversed~=reversed),"beenker-edge-incidence")
          edge.uses[#edge.uses+1]={cell=id,reversed=reversed,visible=keep}
          if keep then
            if not visible_vertices[from] then
              local physical,internal=exact_points(c.corners[k],phase.center)
              visible_vertices[from]={id=vertex_id(from),point=world(c.points[k]),lift=c.corners[k],
                physical=physical,internal=internal}
            end
            visible_edges[ekey]=true
            boundary[k]={edge=edge_id(ekey),reversed=reversed}
          end
        end
        if keep then
          assert(#cells<1000,"beenker-cell-budget")
          local first,angle=1,45*(i-1)
          if j-i==3 then first,angle=2,45*(j-1) end
          cells[#cells+1]={id=id,prototype=c.prototype,chirality=1,address=c.address,base_lift=c.corners[1],
            boundary=boundary,ties=c.ties,
            isometry={rotation_degrees=angle,reflection=false,translation=world(c.points[first])}}
          counts[c.prototype]=counts[c.prototype]+1
          for _,tie in ipairs(c.ties) do
            tie_count=tie_count+1
            if tie.side>0 then positive_ties=positive_ties+1 else negative_ties=negative_ties+1 end
          end
        end
      end
    end end
  end end
  local interior,cuts=0,0
  for _,k in ipairs(sorted_keys(visible_edges)) do
    local edge=all_edges[k]
    assert(#edge.uses==2,"beenker-insufficient-neighbor-halo")
    local global,selected={},{}
    for _,use in ipairs(edge.uses) do
      global[#global+1]=use.cell
      if use.visible then selected[#selected+1]=use.cell end
    end
    table.sort(global,P.byte_less);table.sort(selected,P.byte_less)
    local inside=#selected==2
    if inside then interior=interior+1 else cuts=cuts+1 end
    edges[#edges+1]={id=edge_id(k),from=vertex_id(edge.from),to=vertex_id(edge.to),owner=selected[1],
      role=inside and "interior" or "patch_boundary",boundary_reason=inside and "none" or "query_cut",
      global_owner=global[1],global_cells=global}
  end
  for _,k in ipairs(sorted_keys(visible_vertices)) do vertices[#vertices+1]=visible_vertices[k] end
  assert(#cells>0,"beenker-empty-patch")
  if context then context:consume("objects",#cells+#edges+#vertices) end
  local certificate={method=M.VERSION,source="Beenker 1982, §§2.2–2.3 and 5.1–5.3",phase=phase,
    step_cm=step,frame=P.plain(frame),normalized_query=query,normalized_selection_box=selected_box,
    line_ranges=limits,query_horizon_edge_units=64,physical_internal_denominator=2,
    neighbor_patch_tiles=wide_count,candidate_crossings=examined,counts=counts,
    interior_seams=interior,query_cuts=cuts,ties={count=tie_count,positive=positive_ties,negative=negative_ties},
    checks={"exact algebraic grid decisions and coherent singular-limit ties",
      "integer lifts and complementary physical/internal coordinates",
      "canonical tile incidence with globally owned opposite seams",
      "bounded finite query with a reconstructed neighbor halo"}}
  return {prefix=prefix,tiling={vertices=vertices,edges=edges,cells=cells},certificate=certificate}
end

function M.definition()
  return P.definition({id="tiling/ammann-beenker",version="1",family="beenker-tetragrid",
    units="cm",capabilities={"tiling"},parameters={edge_length={type="number",minimum=.2,maximum=2,required=true},
      phase={type="string",enum={"offset","centered","zero-plus","zero-minus"}}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Fixed rational phase and physical frame",
      "A square and 45-degree rhombus from the exact source tetragrid",
      "Explicit coherent limits for singular zero phase, with finite coverage distinct from nonperiodicity"}})
end
local function routes()
  local registry=require("pattern_aperiodic").route_registry()
  registry.register("projection_multigrid",{construct=construct,validate=function(p)
    return #p.tiling.cells==p.certificate.counts.square+p.certificate.counts.rhombus
      and #p.certificate.phase.regularity==4
  end})
  return registry
end
local function validate(x)
  local e=x.extensions.beenker
  local registry=routes()
  assert(e.route=="projection_multigrid" and P.serialize(e.request.frame)==P.serialize(x.frame),"beenker-frame-record")
  assert(P.serialize(e.capabilities)==P.serialize(registry.capabilities()),"beenker-route-certificate")
  local actual=registry.construct(e.route,P.plain(e.request))
  assert(P.serialize(actual.tiling)==P.serialize(x.structures.tiling),"beenker-lift-and-incidence-reconstruction")
  assert(P.serialize(actual.certificate)==P.serialize(e.certificate),"beenker-certificate-reconstruction")
  return {ok=true,checks=P.plain(e.certificate.checks),construction=P.plain(e.certificate)}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end
local colors={clean={square={.21,.38,.49},rhombus={.78,.57,.32}},
  diagnostic={square={.78,.86,.88},rhombus={.92,.78,.56}}}
local function lower(x,v,style)
  for k in pairs(style) do assert(k=="display","beenker-style:"..k) end
  local display=style.display or "clean"
  local fill=assert(colors[display],"beenker-display")
  local request=x.extensions.beenker.request
  local transform=P.plain(v.transform)
  local inverse=G.inverse(transform,G.policy("cm",request.step_cm))
  local crop=v.crop
  local box=request.world_query
  for _,corner in ipairs{{crop[1],crop[2]},{crop[3],crop[2]},{crop[3],crop[4]},{crop[1],crop[4]}} do
    local p=G.transform(corner,inverse)
    assert(p[1]>=box[1]-1e-10 and p[1]<=box[3]+1e-10 and p[2]>=box[2]-1e-10
      and p[2]<=box[4]+1e-10,"beenker-view-outside-certified-query")
  end
  local world,page,edges={},{},{}
  local ops=P.array()
  for _,vertex in ipairs(x.structures.tiling.vertices) do
    world[vertex.id]=vertex.point;page[vertex.id]=G.transform(vertex.point,transform)
  end
  for _,e in ipairs(x.structures.tiling.edges) do edges[e.id]=e end
  for _,c in ipairs(x.structures.tiling.cells) do
    local commands,points={},{}
    for i,use in ipairs(c.boundary) do
      local edge=edges[use.edge]
      local id=use.reversed and edge.to or edge.from
      local p=world[id]
      commands[i]={i==1 and "M" or "L",p[1],p[2]}
      points[i]=page[id]
    end
    if intersects(bounds(points),crop,0) then
      commands[5]={"Z"}
      local color=fill[c.prototype]
      if display=="diagnostic" and #c.ties>0 then
        if #c.ties==2 then color={.64,.55,.69}
        elseif c.ties[1].side>0 then color={.53,.70,.60}
        else color={.82,.55,.46} end
      end
      ops[#ops+1]={op="path",semantic_ref=c.id,commands=commands,transform=transform,
        paint={fill=color}}
    end
  end
  local width=.012
  local pad=width*math.sqrt(transform[1]^2+transform[2]^2+transform[3]^2+transform[4]^2)
  for _,e in ipairs(x.structures.tiling.edges) do
    if intersects(bounds{page[e.from],page[e.to]},crop,pad) then
      local p,q=world[e.from],world[e.to]
      local stroke=display=="diagnostic" and e.role=="patch_boundary" and {.63,.19,.22} or {.12,.21,.28}
      ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",p[1],p[2]},{"L",q[1],q[2]}},
        transform=transform,paint={stroke=stroke,stroke_width=width}}
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end
function M.register(registry)
  local d,r=M.definition(),routes()
  registry:register(d,{generate=function(s,context)
    local request={phase=s.parameters.phase or "offset",step_cm=s.parameters.edge_length,
      frame=P.plain(context.frame),world_query=P.plain(s.document.bounds)}
    local built=r.construct("projection_multigrid",request,context)
    return {id=built.prefix.."/query/"..H.value("beenker/query",request),definition_ref={id=d.id,version=d.version},
      frame=P.plain(context.frame),structures={tiling=built.tiling},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={beenker={route="projection_multigrid",request=request,certificate=built.certificate,
        capabilities=P.plain(r.capabilities())}}}
  end,validate=validate,lower=lower})
  return d
end
return M
