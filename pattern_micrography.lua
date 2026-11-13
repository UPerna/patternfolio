local P,H,G=require("pattern"),require("pattern_hash"),require("pattern_geometry")
local F,S=require("pattern_micro_field"),require("pattern_stroke_field")
local M={VERSION="digital-micrography-monotone-v1"}
local font_digest="9b9f100958cca036fcc3102719c91ba3804a362ebc215d5ecc16d6f38d9add69"
local font_resource_digest="29c4e364cd81b53416894f8b9f363a0ac0c76abb3c2aadff0dfd7f24c300c9a6"
local abs,min,max,sqrt=math.abs,math.min,math.max,math.sqrt
local function finite(n)return type(n)=='number'and n==n and abs(n)<math.huge end

local function stop(code,receipt)
  error({code="micrography_"..code,message="Micrography: "..code,solver=receipt},0)
end

local function input(s)
  for k in pairs(s.inputs) do
    assert(k=="text" or k=="panel" or k=="font" or k=="fixed","micrography-input:"..k)
  end
  assert(next(P.plain(s.constraints))==nil and #s.document.protected_regions==0,"micrography-use-explicit-panel")
  local q,a=s.document.bounds,s.parameters
  local panel=s.inputs.panel or {{q[1],q[2]},{q[3],q[2]},{q[3],q[4]},{q[1],q[4]}}
  assert(type(panel)=="table" and #panel==4,"micrography-four-sided-convex-panel")
  local clean={}
  for i,p in ipairs(panel) do
    clean[i]=S.point(p)
    assert(p[1]>=q[1] and p[1]<=q[3] and p[2]>=q[2] and p[2]<=q[4],"micrography-panel-outside-document")
  end
  for i,u in ipairs(clean) do
    local v=clean[i%4+1]
    for j,p in ipairs(clean) do
      if j~=i and j~=i%4+1 then
        assert((v[1]-u[1])*(p[2]-u[2])-(v[2]-u[2])*(p[1]-u[1])>1e-7,"micrography-panel-not-convex")
      end
    end
  end
  local text=s.inputs.text
  assert(type(text)=="string" and #text>0 and #text<=2200 and utf8.len(text) and
    not text:match("^ ") and not text:match(" $") and not text:match("  "),"micrography-text-profile")
  local font=s.inputs.font
  assert(type(font)=="table" and font.id=="font/micrography" and font.font_sha256==font_digest,"micrography-pinned-font")
  local fixed,seen=P.array(),{}
  if s.inputs.fixed then
    assert(type(s.inputs.fixed)=="table" and #s.inputs.fixed<=12,"micrography-fixed-boundary-count")
    for i,v in ipairs(s.inputs.fixed) do
      assert(#v==2 and type(v[1])=="number" and v[1]%1==0 and v[1]>=1 and v[1]<=12 and
        (v[2]==0 or v[2]==1) and not seen[v[1]],"micrography-fixed-label")
      fixed[i]=P.plain(v);seen[v[1]]=true
    end
  end
  return {panel=clean,bounds=P.plain(q),text=text,font=P.plain(font),fixed=fixed,size=a.size or .34,
    min_size=a.min_size or .27,spacing=a.spacing or 1.34,omega=a.omega or 1,step=a.step or .065,
    iterations=a.iterations or 3500,max_curvature=a.max_curvature or 1.1}
end

local function shape(text,font)
  local cmap={}
  for _,g in ipairs(font.glyphs) do cmap[g.unicode]=g end
  local codepoints={}
  for _,c in utf8.codes(text) do codepoints[#codepoints+1]=utf8.char(c) end
  local graphemes={}
  for _,v in ipairs(codepoints) do
    if v=="\204\129" then
      assert(#graphemes>0 and cmap[graphemes[#graphemes]..v],"micrography-unsupported-combining-sequence")
      graphemes[#graphemes]=graphemes[#graphemes]..v
    else
      assert(cmap[v],"micrography-unsupported-script-or-glyph")
      graphemes[#graphemes+1]=v
    end
  end
  local groups,word={},{}
  local i=1
  while i<=#graphemes do
    local token=graphemes[i]
    local count=1
    if token=="f" and (graphemes[i+1]=="i" or graphemes[i+1]=="l") then
      token=token..graphemes[i+1]
      count=2
    end
    local g=assert(cmap[token],"micrography-missing-shaped-glyph")
    word[#word+1]={glyph=g,first=i,last=i+count-1}
    if token==" " then groups[#groups+1]=word;word={} end
    i=i+count
  end
  if #word>0 then groups[#groups+1]=word end
  return groups,graphemes
end

local function left_seed(panel,y,padding)
  local x=math.huge
  for i,a in ipairs(panel) do
    local b=panel[i%4+1]
    if (y>=min(a[2],b[2]) and y<=max(a[2],b[2])) and abs(a[2]-b[2])>1e-10 then
      local u=(y-a[2])/(b[2]-a[2])
      x=min(x,a[1]+u*(b[1]-a[1]))
    end
  end
  if x==math.huge then return nil end
  for i=2,6 do
    local p={x+padding*i,y}
    if F.contained(panel,p,padding) then return p end
  end
end

local function lines(q,field)
  local top,bottom=-math.huge,math.huge
  for _,v in ipairs(q.panel) do top=max(top,v[2]);bottom=min(bottom,v[2]) end
  local out={}
  local separation=q.size*q.spacing
  local padding=q.size*.86
  local max_steps=math.ceil((q.bounds[3]-q.bounds[1])*1.6/q.step)
  assert(max_steps<=800,"micrography-tracing-horizon")
  for y=top-padding,bottom+padding,-separation*1.18 do
    local p=left_seed(q.panel,y,padding)
    if p then
      local points,arc={p},{0}
      local curvature=0
      local reason="step_budget"
      local last_angle
      for _=1,max_steps do
        local u=F.at(field,p)
        if not u then reason="field_domain";break end
        local middle={p[1]+q.step*u[1]/2,p[2]+q.step*u[2]/2}
        local v,angle=F.at(field,middle)
        if not v then reason="panel";break end
        local next_p={p[1]+q.step*v[1],p[2]+q.step*v[2]}
        if not F.contained(q.panel,next_p,padding) then reason="panel";break end
        local k=last_angle and abs(angle-last_angle)/q.step or 0
        if k>q.max_curvature then reason="curvature";break end
        local allowed=true
        for _,line in ipairs(out) do
          for i,a in ipairs(line.points) do
            local b=line.points[i+1]
            if b and b[1]>=p[1]-separation and a[1]<=next_p[1]+separation and
              S.segment_gap2(p,next_p,a,b)<separation^2 then allowed=false;break end
          end
          if not allowed then break end
        end
        if not allowed then reason="separation";break end
        curvature=max(curvature,k)
        points[#points+1]=next_p
        arc[#arc+1]=arc[#arc]+q.step
        p,last_angle=next_p,angle
      end
      if arc[#arc]>=q.size*5 then
        out[#out+1]={points=points,arc=arc,length=arc[#arc],max_curvature=curvature,stop=reason}
      end
    end
  end
  return out
end

local function location(line,s)
  local i=min(#line.points-1,math.floor(s/(line.arc[2]-line.arc[1]))+1)
  local t=(s-line.arc[i])/(line.arc[i+1]-line.arc[i])
  local p,q=line.points[i],line.points[i+1]
  return {p[1]+t*(q[1]-p[1]),p[2]+t*(q[2]-p[2])},math.atan(q[2]-p[2],q[1]-p[1])
end

local function corners(g,place,scale)
  local l,b,r,t=table.unpack(g.bounds)
  local c,s=math.cos(place.rotation),math.sin(place.rotation)
  local points={}
  for i,p in ipairs{{l,b},{r,b},{r,t},{l,t}} do
    points[i]={place.offset[1]+scale*(c*p[1]-s*p[2]),place.offset[2]+scale*(s*p[1]+c*p[2])}
  end
  return points
end

local function layout(q,field,groups,clusters)
  local streamlines=lines(q,field)
  local runs,order,positions=P.array(),P.array(),P.array()
  local scale=q.size/q.font.units_per_em
  local spacing=q.size*.019
  local at=1
  for i,line in ipairs(streamlines) do
    local glyphs,span,chunk=P.array(),P.array(),{}
    local cursor=q.size*.18
    while groups[at] do
      local advance=0
      for _,g in ipairs(groups[at]) do advance=advance+g.glyph.advance*scale+spacing end
      if cursor+advance+q.size*.20>line.length then break end
      for _,g in ipairs(groups[at]) do
        local p,rotation=location(line,cursor)
        local placement={glyph_ref=g.glyph.id,offset=p,rotation=rotation}
        for _,corner in ipairs(corners(g.glyph,placement,scale)) do
          assert(F.contained(q.panel,corner,0),"micrography-glyph-outside-panel")
        end
        glyphs[#glyphs+1]=placement
        span[#span+1]={g.first,g.last}
        chunk[#chunk+1]=g.glyph.unicode
        cursor=cursor+g.glyph.advance*scale+spacing
      end
      at=at+1
    end
    if #glyphs>0 then
      local id="micrography/line/"..i
      runs[#runs+1]={id=id,text=table.concat(chunk),direction="ltr"}
      order[#order+1]=id
      positions[#positions+1]={line=i,glyphs=glyphs,spans=span}
    end
    if not groups[at] then break end
  end
  local solver={algorithm=F.VERSION,search="bounded-exact-binary-labels",examined=field.labels.examined,
    labels=field.labels.mask,objective=field.labels.energy,field_iterations=field.iterations,field_residual=field.residual,
    streamlines=#streamlines,words_placed=at-1,words_total=#groups,graphemes=#clusters}
  if at<=#groups then solver.status="insufficient_space";stop("insufficient_space",solver) end
  solver.status="complete"
  return {runs=runs,reading_order=order},positions,P.array(streamlines),solver
end

function M.definition()
  return P.definition({id="text/digital-micrography",version="1",family="boundary-optimized-micrography",
    units="cm",capabilities={"text","field"},parameters={
      size={type="number",minimum=.22,maximum=.65},min_size={type="number",minimum=.22,maximum=.65},
      spacing={type="number",minimum=1.25,maximum=2.1},omega={type="number",minimum=.2,maximum=5},
      step={type="number",minimum=.035,maximum=.14},iterations={type="integer",minimum=1,maximum=5000},
      max_curvature={type="number",minimum=.002,maximum=2.5}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Convex quadrilateral, exact signed boundary labeling and finite doubled-angle field",
      "Monotone separated streamlines and bounded Latin/Greek grapheme shaping",
      "Pinned GUST font with visible outlines and searchable Unicode layers"}})
end

local function field_samples(field,q)
  local samples=P.array()
  for i,p in ipairs(field.points) do
    local r=field.vectors[i]
    local angle=.5*math.atan(r[2],r[1])
    samples[i]={id="micrography/field/"..i,point=p,vector={math.cos(angle),math.sin(angle)},density=1}
  end
  return {representation="samples",domain={bounds=q.bounds},samples=samples}
end

-- Reconstruct the claimed field/layout. Continuous leaves admit only the same
-- binary64 roundoff bound used by the independent native/browser checker;
-- connectivity, labels, spans, indices and unknown leaves remain exact.
local continuous={
  '^field/points/%d+/[12]$','^field/vectors/%d+/[12]$',
  '^field/residual$','^field/min_representation_x$','^field/max_representation_x$',
  '^field/labels/attraction_scale$','^field/labels/energy$',
  '^field/labels/all_aligned$','^field/labels/none_aligned$',
  '^field/labels/edges/%d+/3$','^field/labels/samples/%d+/attraction$',
  '^field/labels/samples/%d+/point/[12]$','^field/labels/samples/%d+/tangent/[12]$',
  '^field/labels/samples/%d+/opposite/%d+/distance$','^field/labels/samples/%d+/opposite/%d+/alignment$',
  '^positions/%d+/glyphs/%d+/offset/[12]$','^positions/%d+/glyphs/%d+/rotation$',
  '^streamlines/%d+/points/%d+/[12]$','^streamlines/%d+/arc/%d+$',
  '^streamlines/%d+/length$','^streamlines/%d+/max_curvature$',
  '^solver/field_residual$','^solver/objective$'}
continuous[#continuous+1]='^structure/field/samples/%d+/point/[12]$'
continuous[#continuous+1]='^structure/field/samples/%d+/vector/[12]$'
local function reconstructed(actual,expected,path)
  assert(type(actual)==type(expected),'micrography-reconstruction-type:'..path)
  if type(expected)=='table'then
    for k,v in pairs(expected)do reconstructed(actual[k],v,path..'/'..tostring(k))end
    for k in pairs(actual)do assert(expected[k]~=nil,'micrography-reconstruction-key:'..path)end
  elseif type(expected)=='number'then
    assert(finite(actual),'micrography-reconstruction-nonfinite:'..path)
    if actual~=expected then
      local permitted=false;for _,pattern in ipairs(continuous)do if path:match(pattern)then permitted=true;break end end
      assert(permitted and abs(actual-expected)<=min(1e-10,32*2^-52*max(1,abs(actual),abs(expected))),
        'micrography-reconstruction-value:'..path)
    end
  else assert(actual==expected,'micrography-reconstruction-value:'..path)end
end
local function validate(x,context)
  local e=x.extensions.micrography
  local t=x.structures.text
  local q=e.request
  assert(H.value('micrography/font-resource',q.font)==font_resource_digest,'micrography-font-resource-integrity')
  -- Admitted requests have a bounded quadrilateral mesh and bounded solver.
  local parameters={};for key,rule in pairs(M.definition().parameters)do
    local v=q[key];assert(finite(v)and v>=rule.minimum and v<=rule.maximum and (rule.type~='integer'or v%1==0),'micrography-request-range:'..key);parameters[key]=v
  end
  local normalized=input({parameters=parameters,inputs={panel=q.panel,text=q.text,font=q.font,fixed=q.fixed},constraints={},document={bounds=q.bounds,protected_regions=P.array()}})
  assert(P.serialize(normalized)==P.serialize(q),'micrography-request-normalization')
  local field=F.solve(q.panel,q.size,q.omega,q.fixed,12,q.iterations,context and function(n)context:consume('operations',n)end)
  reconstructed(e.field,field,'field')
  local groups,source_clusters=shape(q.text,q.font)
  local text,positions,streamlines,solver=layout(q,field,groups,source_clusters)
  reconstructed(e.positions,positions,'positions');reconstructed(e.streamlines,streamlines,'streamlines')
  reconstructed(e.solver,solver,'solver');reconstructed(e.clusters,source_clusters,'clusters')
  reconstructed(t,text,'text')
  reconstructed(x.structures.field,field_samples(e.field,e.request),'structure/field')
  local clusters={}
  local next_cluster=1
  local cmap={}
  for _,g in ipairs(e.request.font.glyphs) do cmap[g.id]=g end
  for i,run in ipairs(t.runs) do
    clusters[#clusters+1]=run.text
    assert(run.id==t.reading_order[i],"micrography-run-order")
    local line=e.positions[i]
    local parts={}
    for j,g in ipairs(line.glyphs) do
      local span=line.spans[j]
      assert(span[1]==next_cluster and span[2]>=span[1],"micrography-cluster-conservation")
      next_cluster=span[2]+1
      local glyph=cmap[g.glyph_ref]
      local source={}
      for k=span[1],span[2] do source[#source+1]=e.clusters[k] end
      assert(table.concat(source)==glyph.unicode,"micrography-glyph-cluster-mapping")
      parts[#parts+1]=glyph.unicode
      for _,p in ipairs(corners(glyph,g,e.request.size/e.request.font.units_per_em)) do
        assert(F.contained(e.request.panel,p,0),"micrography-glyph-containment")
      end
    end
    assert(table.concat(parts)==run.text,"micrography-run-content")
  end
  assert(table.concat(clusters)==e.request.text and next_cluster==#e.clusters+1,"micrography-text-conservation")
  return {ok=true,solver=P.plain(e.solver),checks={"Pinned grapheme-to-glyph and run order verified",
    "Doubled-angle samples reconstructed","Field, boundary labels, mesh references and complete layout reconstructed",
    "Glyph envelopes contained in the source panel"}}
end

local function lower(x,v,style)
  assert(next(P.plain(style))==nil and #v.protected_regions==0,"micrography-view-with-hidden-text")
  local e=x.extensions.micrography
  local transform=P.plain(v.transform)
  local crop=v.crop
  local cmap={}
  for _,g in ipairs(e.request.font.glyphs) do cmap[g.id]=g end
  local ops=P.array()
  local order=x.structures.text.reading_order
  for i,run in ipairs(x.structures.text.runs) do
    local gs=e.positions[i].glyphs
    for _,g in ipairs(gs) do
      for _,p in ipairs(corners(cmap[g.glyph_ref],g,e.request.size/e.request.font.units_per_em)) do
        local q=G.transform(p,transform)
        assert(q[1]>=crop[1]-1e-10 and q[1]<=crop[3]+1e-10 and q[2]>=crop[2]-1e-10 and q[2]<=crop[4]+1e-10,
          "micrography-crop-would-hide-text")
      end
    end
    ops[i]={op="text",semantic_ref=run.id,font_ref=e.request.font.id,text=run.text,origin={0,0},
      size=e.request.size,glyphs=P.plain(gs),paint={fill={.10,.17,.24}},transform=transform}
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,operations=ops,
    resources={P.plain(e.request.font)},reading_order=P.plain(order),clip={bounds=P.plain(crop),protected_regions=P.array()}}
end

function M.register(reg)
  local d=M.definition()
  reg:register(d,{validate_inputs=function(s) input(s);return true end,generate=function(s,c)
    local q=input(s)
    if q.size<q.min_size then stop("legibility",{status="size_below_minimum",size=q.size,minimum=q.min_size}) end
    assert(H.value("micrography/font-resource",q.font)==font_resource_digest,"micrography-font-resource-integrity")
    local groups,clusters=shape(q.text,q.font)
    -- Text semantics count against the caller's object budget before solving.
    c:consume("objects",#clusters)
    local field=F.solve(q.panel,q.size,q.omega,q.fixed,12,q.iterations,function(n) c:consume("operations",n) end)
    local text,positions,lines,solver=layout(q,field,groups,clusters)
    local identity=P.plain(q)
    identity.font=q.font.font_sha256
    return {id="micrography/"..H.value("micrography/design",identity),
      definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={text=text,field=field_samples(field,q)},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={micrography={request=q,field=field,streamlines=lines,positions=positions,
        clusters=P.array(clusters),solver=solver,export="visible positioned outlines with actual Unicode text layers"}}}
  end,validate=validate,lower=lower})
  return d
end
return M
