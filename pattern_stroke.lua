local P,H=require("pattern"),require("pattern_hash")
local F,X=require("pattern_stroke_field"),require("pattern_stroke_examples")
local M={VERSION="bounded-stroke-textures-v1"}
local min,max,sqrt=math.min,math.max,math.sqrt
local ink={.12,.19,.26}

local function site_grid(f,spacing,padding)
  local x0,y0,x1,y1=table.unpack(f.bounds)
  local nx,ny=math.floor((x1-x0)/spacing),math.floor((y1-y0)/spacing)
  assert(nx*ny<=2500,"stroke-seed-grid-budget")
  local sites={}
  for j=1,ny do
    for i=1,nx do
      local p={x0+(i-.5)*(x1-x0)/nx,y0+(j-.5)*(y1-y0)/ny}
      if F.admissible(f,p,p,padding) then sites[#sites+1]=p end
    end
  end
  local cx,cy=(x0+x1)/2,(y0+y1)/2
  table.sort(sites,function(a,b)
    local da,db=(a[1]-cx)^2+(a[2]-cy)^2,(b[1]-cx)^2+(b[2]-cy)^2
    if da==db then
      if a[2]==b[2] then return a[1]<b[1] end
      return a[2]<b[2]
    end
    return da<db
  end)
  return sites
end

local function hatching(f,a,c)
  local strokes,stops,segments=P.array(),P.array(),{}
  local function separated(p,q,own)
    for _,s in ipairs(segments) do
      c:consume("operations",1)
      if F.segment_gap2(p,q,s[1],s[2])<(a.spacing+a.width)^2 then return false end
    end
    for j=1,#own-3 do
      c:consume("operations",1)
      if F.segment_gap2(p,q,own[j],own[j+1])<(a.step*.8)^2 then return false end
    end
    return true
  end
  for _,seed in ipairs(site_grid(f,a.spacing,a.width/2)) do
    if #strokes>=a.count then break end
    local forward=F.integrate(f,seed,a.step,a.steps,a.width/2,{segment=separated})
    local backward=F.integrate(f,seed,a.step,a.steps,a.width/2,{reverse=true,segment=function(p,q,own)
      if not separated(p,q,own) then return false end
      for j=3,#forward.points-1 do
        c:consume("operations",1)
        if F.segment_gap2(p,q,forward.points[j],forward.points[j+1])<(a.step*.8)^2 then return false end
      end
      return true
    end})
    stops[#stops+1]={seed=seed,forward=forward.stop,backward=backward.stop}
    local points={}
    for j=#backward.points,2,-1 do points[#points+1]=backward.points[j] end
    for _,p in ipairs(forward.points) do points[#points+1]=p end
    if #points>=3 then
      strokes[#strokes+1]={points=points,width=a.width,color=ink,role="stroke",site=#stops}
      for j=1,#points-1 do segments[#segments+1]={points[j],points[j+1]} end
    end
  end
  return strokes,{stops=stops}
end

local function stippling(f,a,c)
  local rng=c:stream("stippling","density")
  local out=P.array()
  local l,b,r,t=table.unpack(f.bounds)
  local attempted=0
  local rejection={density=0,domain=0,spacing=0}
  for i=1,a.attempts do
    attempted=i
    local p={l+(r-l)*rng.u(),b+(t-b)*rng.u()}
    if rng.u()>F.density(f,p) then rejection.density=rejection.density+1
    elseif not F.admissible(f,p,p,a.width/2) then rejection.domain=rejection.domain+1
    else
      local fits=true
      for _,s in ipairs(out) do
        c:consume("operations",1)
        if F.distance2(p,s.points[1],s.points[1])<(a.spacing+a.width)^2 then fits=false;break end
      end
      if fits then
        out[#out+1]={points={p},width=a.width,color=ink,role="dot",site=i}
        if #out==a.count then break end
      else rejection.spacing=rejection.spacing+1 end
    end
  end
  return out,{attempted=attempted,rejections=rejection,status=#out==a.count and "complete" or "attempt_budget"}
end

local function shifted_grid(f,a,rng,data,c)
  local g=site_grid(f,a.spacing,.01)
  local sites={}
  for i,p in ipairs(g) do
    local q={p[1]+(rng.u()-.5)*a.spacing*.55,p[2]+(rng.u()-.5)*a.spacing*.55}
    sites[i]=F.admissible(f,q,q,.01) and q or p
    if i>=a.count then break end
  end
  local trace=P.array()
  if a.profile=="group" and #sites>=2 then
    local function ratio(distances)
      local sum,square=0,0
      for _,v in ipairs(distances) do sum,square=sum+v,square+v*v end
      local mean=sum/#distances
      return sqrt(max(0,square/#distances-mean*mean))/mean
    end
    local observed={}
    for i,p in ipairs(data.relations) do observed[i]=p.proximity end
    local target=ratio(observed)
    local grid=site_grid(f,max(a.spacing/3,.10),.01)
    for k=0,a.relax do
      local distances={}
      for i,p in ipairs(sites) do
        local best=math.huge
        for j,q in ipairs(sites) do
          if i~=j then best=min(best,F.distance2(p,q,q)) end
        end
        distances[i]=sqrt(best)
      end
      local variance=ratio(distances)
      trace[#trace+1]={iteration=k,relative_deviation=variance,target=target}
      if variance<=target or k==a.relax then break end
      local acc={}
      for i=1,#sites do acc[i]={0,0,0} end
      for _,p in ipairs(grid) do
        local winner,d=1,math.huge
        for j,q in ipairs(sites) do
          local ds=F.distance2(p,q,q)
          if ds<d then winner,d=j,ds end
        end
        local x=acc[winner]
        x[1],x[2],x[3]=x[1]+p[1],x[2]+p[2],x[3]+1
      end
      c:consume("operations",#grid*#sites)
      for i,x in ipairs(acc) do
        if x[3]>0 then
          local p={x[1]/x[3],x[2]/x[3]}
          if F.admissible(f,sites[i],p,.01) then sites[i]=p end
        end
      end
    end
  end
  return sites,trace
end

local function synthesis(f,a,raw,c)
  local data=X.analyze(raw,a.cluster)
  local rng=c:stream("example","stroke-groups")
  local sites,relaxation=shifted_grid(f,a,rng,data,c)
  local previous={}
  local function allowed(strokes,element)
    local candidates={}
    for _,s in ipairs(strokes) do
      for j=1,max(1,#s.points-1) do
        local p,q=s.points[j],s.points[j+1] or s.points[j]
        if not F.admissible(f,p,q,s.width/2) then return false end
        for _,v in ipairs(previous) do
          c:consume("operations",1)
          if F.segment_gap2(p,q,v[1],v[2])<(a.clearance+(s.width+v[3])/2)^2 then return false end
        end
        candidates[#candidates+1]={p,q,s.width}
      end
    end
    for _,v in ipairs(candidates) do previous[#previous+1]=v end
    return true
  end
  local elements,strokes,decisions=X.synthesize(data,sites,a,rng,allowed)
  return P.array(strokes),{analysis=data,decisions=P.array(decisions),elements=P.array(elements),relaxation=relaxation}
end

local function controls(p)
  return {mode=p.mode,count=p.count,spacing=p.spacing,width=p.width or .028,step=p.step or .055,
    steps=p.steps or 32,attempts=p.attempts or 3000,profile=p.profile or "causal",behavior=p.behavior or "cloning",
    cluster=p.cluster or .10,scale=p.scale or 1,radius=p.radius or .9,threshold=p.threshold or .7,
    correction=p.correction or .45,relax=p.relax or 4,clearance=p.clearance or .018}
end

function M.definition()
  return P.definition({id="stroke/fields-and-examples",version="1",family="stroke-field-texture",
    units="cm",capabilities={"field"},parameters={
      mode={type="string",enum={"hatching","stippling","example"},required=true},
      count={type="integer",minimum=1,maximum=300,required=true},
      spacing={type="number",minimum=.05,maximum=2,required=true},
      width={type="number",minimum=.008,maximum=.2},step={type="number",minimum=.015,maximum=.2},
      steps={type="integer",minimum=1,maximum=75},attempts={type="integer",minimum=1,maximum=15000},
      profile={type="string",enum={"causal","group","independent"}},
      behavior={type="string",enum={"sampling","copying","cloning"}},
      cluster={type="number",minimum=.01,maximum=.5},scale={type="number",minimum=.4,maximum=2.5},
      radius={type="number",minimum=.2,maximum=3},threshold={type="number",minimum=.05,maximum=3},
      correction={type="number",minimum=0,maximum=1},relax={type="integer",minimum=0,maximum=12},
      clearance={type="number",minimum=0,maximum=.2}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Centimeter analytic direction and density fields with circular holes",
      "Bounded midpoint streamlines, separated stipples and independently analyzed stroke examples",
      "Greedy example elements, causal neighbor matching, and nearest-pair group behaviors"}})
end

local function field(s)
  assert(next(P.plain(s.constraints))==nil,"stroke-unsupported-constraints")
  for k in pairs(s.inputs) do assert(k=="field" or k=="holes" or k=="example","stroke-input:"..k) end
  assert((s.parameters.mode=="example")== (s.inputs.example~=nil),"stroke-example-mode")
  local f=F.new(s.document.bounds,s.inputs.holes,s.inputs.field)
  assert(f.bounds[3]-f.bounds[1]<=12 and f.bounds[4]-f.bounds[2]<=12,"stroke-field-size")
  return f
end

local function samples(strokes,f)
  local out=P.array()
  for i,s in ipairs(strokes) do
    local p=s.points[1]
    local v=F.direction(f,p) or {0,0}
    out[i]={id="stroke/mark/"..i,point=p,vector=v,density=F.density(f,p)}
  end
  return {representation="samples",domain={bounds=f.bounds},samples=out}
end

local function validate(x)
  local e=x.extensions.stroke
  assert(P.serialize(samples(e.strokes,e.field))==P.serialize(x.structures.field),"stroke-field-reconstruction")
  for _,s in ipairs(e.strokes) do
    assert(#s.points>=1 and s.width>0,"stroke-empty-mark")
    for j=1,max(1,#s.points-1) do
      assert(F.admissible(e.field,s.points[j],s.points[j+1] or s.points[j],s.width/2),"stroke-outside-domain")
    end
  end
  return {ok=true,checks={"Stroke segments and ink radius remain admissible","Field samples reconstructed from stroke geometry"}}
end

local function circle(p,r)
  local x,y=p[1],p[2]
  local k=.5522847498307936*r
  return {{"M",x+r,y},{"C",x+r,y+k,x+k,y+r,x,y+r},{"C",x-k,y+r,x-r,y+k,x-r,y},
    {"C",x-r,y-k,x-k,y-r,x,y-r},{"C",x+k,y-r,x+r,y-k,x+r,y},{"Z"}}
end

local function lower(x,v,style)
  assert(next(P.plain(style))==nil,"stroke-unsupported-style")
  local ops=P.array()
  for i,s in ipairs(x.extensions.stroke.strokes) do
    local path,paint
    if s.role=="dot" then path,paint=circle(s.points[1],s.width/2),{fill=s.color}
    else
      path={}
      for j,p in ipairs(s.points) do path[j]={j==1 and "M" or "L",p[1],p[2]} end
      paint={stroke=s.color,stroke_width=s.width,cap="round",join="round"}
    end
    ops[#ops+1]={op="path",semantic_ref="stroke/mark/"..i,commands=path,transform=P.plain(v.transform),paint=paint}
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,operations=ops,
    resources=P.array(),clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)}}
end

function M.register(reg)
  local d=M.definition()
  reg:register(d,{validate_inputs=function(s) field(s);return true end,generate=function(s,c)
    local f,a=field(s),controls(s.parameters)
    local strokes,trace
    if a.mode=="hatching" then strokes,trace=hatching(f,a,c)
    elseif a.mode=="stippling" then strokes,trace=stippling(f,a,c)
    else strokes,trace=synthesis(f,a,s.inputs.example,c) end
    return {id="stroke/"..H.value("stroke/instance",{field=f,controls=a,seed=s.seed,example=P.plain(s.inputs.example),method=M.VERSION}),
      definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={field=samples(strokes,f)},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={stroke={field=f,controls=a,strokes=strokes,trace=trace}}}
  end,validate=validate,lower=lower})
  return d
end

return M


