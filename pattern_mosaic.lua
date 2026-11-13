local P,R,H=require("pattern"),require("pattern_registry"),require("pattern_hash")
local C=require("pattern_mosaic_cpu")
local M={VERSION=C.VERSION}
local function finite(x)
  return type(x)=="number" and x==x and math.abs(x)<=100
end
local function point(p,b)
  assert(type(p)=="table" and #p==2 and finite(p[1]) and finite(p[2]),"mosaic-point")
  assert(p[1]>=b[1] and p[1]<=b[3] and p[2]>=b[2] and p[2]<=b[4],"mosaic-point-outside-bounds")
  return P.plain(p)
end
local function rgb(c)
  assert(type(c)=="table" and #c==3,"mosaic-rgb")
  for _,v in ipairs(c) do assert(finite(v) and v>=0 and v<=1,"mosaic-rgb") end
  return P.plain(c)
end
local function request(s)
  local a,b=s.parameters,s.document.bounds
  local input=s.inputs
  for k in pairs(input) do assert(k=="panel" or k=="features" or k=="image" or k=="witness","mosaic-input:"..k) end
  assert(next(P.plain(s.constraints))==nil,"mosaic-constraints")
  assert(b[3]-b[1]<=20 and b[4]-b[2]<=20,"mosaic-bounds")
  local panel=input.panel or {{b[1],b[2]},{b[3],b[2]},{b[3],b[4]},{b[1],b[4]}}
  assert(type(panel)=="table" and #panel>=3 and #panel<=16,"mosaic-panel-count")
  local area=0
  for i,p in ipairs(panel) do
    point(p,b)
    local q=point(panel[i%#panel+1],b)
    area=area+p[1]*q[2]-p[2]*q[1]
    for j,r in ipairs(panel) do
      if j~=i and j~=i%#panel+1 then
        point(r,b)
        assert((q[1]-p[1])*(r[2]-p[2])-(q[2]-p[2])*(r[1]-p[1])>1e-8,"mosaic-panel-must-be-strictly-convex-ccw")
      end
    end
  end
  local features=input.features or P.array()
  assert(type(features)=="table" and #features<=12,"mosaic-feature-count")
  for _,line in ipairs(features) do
    assert(type(line)=="table" and #line>=2 and #line<=64,"mosaic-feature-point-count")
    for i,p in ipairs(line) do
      point(p,b)
      if i>1 then assert((p[1]-line[i-1][1])^2+(p[2]-line[i-1][2])^2>1e-12,"mosaic-degenerate-feature") end
    end
  end
  local image=input.image
  assert(type(image)=="table" and type(image.layers)=="table" and #image.layers<=12,"mosaic-analytic-image")
  local clean_image={background=rgb(image.background),layers=P.array()}
  for i,l in ipairs(image.layers) do
    assert(l.shape=="ellipse" or l.shape=="band","mosaic-image-layer")
    assert(type(l.extent)=="table" and #l.extent==2 and finite(l.extent[1]) and finite(l.extent[2])
      and l.extent[1]>0 and l.extent[2]>0,"mosaic-image-extent")
    assert(l.shape~="band" or finite(l.curve),"mosaic-image-curve")
    clean_image.layers[i]={shape=l.shape,center=point(l.center,b),extent=P.plain(l.extent),color=rgb(l.color),curve=l.curve}
  end
  return {bounds=P.plain(b),panel=P.plain(panel),panel_area=area/2,features=P.plain(features),image=clean_image,
    count=a.count,size=a.tile_size,sample=a.sample_step,grout=a.grout or .02,
    guided=a.guided~=false,influence=a.influence or .8,aspect=a.aspect or 1,
    size_variation=a.size_variation or 0,exclusion=a.exclusion or 0,avoid_steps=a.avoid_steps or 0,
    iterations=a.iterations or 12,tolerance=a.tolerance or .005,min_scale=a.min_scale or .18}
end

local function sample(image,p)
  local color=image.background
  for _,l in ipairs(image.layers) do
    local x=(p[1]-l.center[1])/l.extent[1]
    local y=(p[2]-l.center[2])/l.extent[2]
    if (l.shape=="ellipse" and x*x+y*y<=1) or (l.shape=="band" and math.abs(x)<=1 and math.abs(y-l.curve*x*x)<=1) then
      color=l.color
    end
  end
  return P.plain(color)
end

local function geometry(q,centers)
  assert(type(centers)=="table" and #centers==q.count,"mosaic-witness-count")
  for _,p in ipairs(centers) do
    point(p,q.bounds)
    assert(C.inside(q.panel,p[1],p[2]),"mosaic-center-outside-panel")
  end
  local tiles,rejected,area=C.pack(q,centers)
  local field={representation="samples",domain={bounds=q.bounds},samples=P.array()}
  for _,t in ipairs(tiles) do
    t.id="mosaic/site/"..t.site
    t.color=sample(q.image,t.center)
    field.samples[#field.samples+1]={id=t.id,point=t.center,vector=t.axis,density=1}
  end
  return field,{tiles=P.array(tiles),rejected=P.array(rejected),area=area,coverage=area/q.panel_area,
    status=#tiles==0 and "empty_packing" or (#rejected>0 and "partial_packing" or "all_sites_packed")}
end

function M.definition()
  return P.definition({id="mosaic/hausner",version="1",family="hausner-decorative-mosaic",units="cm",
    capabilities={"field"},parameters={
      count={type="integer",minimum=1,maximum=320,required=true},
      tile_size={type="number",minimum=.08,maximum=4,required=true},
      sample_step={type="number",minimum=.025,maximum=.5,required=true},
      grout={type="number",minimum=0,maximum=.4},guided={type="boolean"},
      influence={type="number",minimum=.05,maximum=4},aspect={type="number",minimum=1,maximum=3},
      size_variation={type="number",minimum=0,maximum=.6},exclusion={type="number",minimum=0,maximum=4},
      avoid_steps={type="integer",minimum=0,maximum=20},iterations={type="integer",minimum=0,maximum=48},
      tolerance={type="number",minimum=.0001,maximum=.05},min_scale={type="number",minimum=.05,maximum=1}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Convex bounded panel and analytic layered color sampler",
      "CPU samples of rotated weighted L1 pyramids, with artist-feature exclusion and Lloyd updates",
      "Ordered rectangle scale projection with separating-axis grout and explicit rejected sites"}})
end

local function validate(x)
  local e=x.extensions.mosaic
  local field,pack=geometry(e.request,e.centers)
  assert(P.serialize(field)==P.serialize(x.structures.field),"mosaic-field-reconstruction")
  assert(P.serialize(pack)==P.serialize(e.packing),"mosaic-packing-reconstruction")
  assert(e.solver.witness_sha256==H.value("mosaic/centers",e.centers),"mosaic-witness-digest")
  return {ok=true,solver=P.plain(e.solver),construction={coverage=pack.coverage,status=pack.status},checks={"Field samples reconstructed", "Vector packing reconstructed", "Saved centers digest verified"}}
end

local function lower(x,v,style)
  for k in pairs(style) do assert(k=="features","mosaic-style:"..k) end
  assert(style.features==nil or type(style.features)=="boolean","mosaic-feature-overlay")
  local ops=P.array()
  local e=x.extensions.mosaic
  local function draw(ref,points,closed,paint)
    local commands={}
    for i,p in ipairs(points) do commands[i]={i==1 and "M" or "L",p[1],p[2]} end
    if closed then commands[#commands+1]={"Z"} end
    ops[#ops+1]={op="path",semantic_ref=ref,commands=commands,transform=P.plain(v.transform),paint=paint}
  end
  draw(x.id,e.request.panel,true,{fill={.18,.17,.15}})
  for _,t in ipairs(e.packing.tiles) do draw(t.id,t.corners,true,{fill=t.color}) end
  if style.features then
    for _,line in ipairs(e.request.features) do draw(x.id,line,false,{stroke={1,.8,.3},stroke_width=.012}) end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,operations=ops,
    resources=P.array(),clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)}}
end

function M.register(reg)
  local d=M.definition()
  reg:register(d,{validate_inputs=function(s) request(s);return true end,generate=function(s,c)
    local q=request(s)
    -- Charge requested sites before either solving or accepting a witness.
    c:consume("objects",q.count)
    local solver,centers
    if s.inputs.witness then
      centers=P.plain(s.inputs.witness)
      solver={route="replayed",status="saved_centers",evaluations=0}
    else
      local result=C.solve(q,c:stream("lloyd-start","mosaic"),function(n) c:consume("operations",n) end)
      centers=result.centers
      solver={route="sampled_lloyd",status=result.status,initial=result.initial,history=P.array(result.history),
        evaluations=#result.history+1,final_energy=result.final_energy,samples=result.samples}
    end
    solver.algorithm=M.VERSION
    solver.witness_sha256=H.value("mosaic/centers",centers)
    local field,packing=geometry(q,centers)
    local identity=P.plain(q)
    identity.iterations,identity.tolerance,identity.avoid_steps=nil,nil,nil
    return {id="mosaic/"..H.value("mosaic/geometry",{identity=identity,centers=centers}),
      definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={field=field},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={mosaic={request=q,centers=centers,solver=solver,packing=packing}}}
  end,validate=validate,lower=lower})
  return d
end

return M


