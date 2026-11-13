local P,H = require("pattern"),require("pattern_hash")
local Field,Refine,Vector = require("pattern_deco_field"),require("pattern_deco_refine"),require("pattern_deco_vector")
local G = require("pattern_geometry")
local M = {VERSION="decobrush-sdf-arap-v1"}

function M.definition()
  return P.definition({id="decoration/decobrush",version="1",family="example-driven-decorative-brush",
    units="cm",capabilities={"field"},parameters={
      subdivisions={type="integer",minimum=4,maximum=24},
      rows={type="integer",minimum=5,maximum=41},
      refinement_radius={type="number",minimum=.01,maximum=.5}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Closed polygonal exemplar primitives with declared longitudinal spines",
      "Single oriented, nonfolding guide chart with endpoint-specific pieces",
      "Signed distance, anchored ARAP, overlap cuts and masked source-coordinate refinement"}})
end

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end

local function input(s)
  local q = P.plain(s.inputs)
  local a = s.parameters
  assert(type(q.guide)=="table" and #q.guide>=3 and #q.guide<=33,"deco-guide-size")
  assert(type(q.library)=="table" and #q.library>=3 and #q.library<=16,"deco-library-size")
  for _,p in ipairs(q.guide) do
    assert(#p==3 and finite(p[1]) and finite(p[2]) and finite(p[3]) and p[3]>.01 and p[3]<=4,"deco-guide-station")
  end
  for _,piece in ipairs(q.library) do
    assert(piece.role=="start" or piece.role=="middle" or piece.role=="finish","deco-piece-role")
    assert(finite(piece.length) and piece.length>.01 and finite(piece.width) and piece.width>.01
      and finite(piece.turn),"deco-piece-metric")
    assert(type(piece.primitives)=="table" and #piece.primitives>0,"deco-piece-primitives")
    for _,primitive in ipairs(piece.primitives) do
      assert(type(primitive.ring)=="table" and #primitive.ring>=3,"deco-primitive-ring")
      for _,v in ipairs(primitive.ring) do
        assert(#v==2 and finite(v[1]) and finite(v[2]),"deco-primitive-point")
      end
    end
  end
  local edit = q.edit or P.array()
  assert(type(edit)=="table" and #edit<=32,"deco-edit-budget")
  for _,box in ipairs(edit) do
    assert(#box==5 and finite(box[1]) and finite(box[2]) and finite(box[3]) and finite(box[4])
      and box[1]<box[3] and box[2]<box[4] and type(box[5])=="boolean","deco-edit-box")
  end
  return {guide=q.guide,library=q.library,edit=edit,subdivisions=a.subdivisions or 16,
    rows=a.rows or 17,radius=a.refinement_radius or .15,bounds=P.plain(s.document.bounds)}
end

local function samples(field)
  local out=P.array()
  for i=1,field.width do
    local p=field.grid[math.floor(field.height/2)*field.width+i]
    local prev=field.grid[math.floor(field.height/2)*field.width+math.max(1,i-1)]
    local next_point=field.grid[math.floor(field.height/2)*field.width+math.min(field.width,i+1)]
    local dx,dy=next_point.x-prev.x,next_point.y-prev.y
    local norm=math.sqrt(dx*dx+dy*dy)
    out[i]={id="deco/rib/"..i,point={p.x,p.y},vector={dx/norm,dy/norm},density=1}
  end
  return out
end

local function generate(d,s,c)
  local q=input(s)
  local width=(#q.guide-1)*q.subdivisions+1
  assert(width*q.rows<=5000,"deco-grid-budget")
  c:consume("objects",width*q.rows)
  c:consume("operations",width*q.rows*64)
  local f,why=Field.synthesize(q.guide,q.library,{subdivisions=q.subdivisions,rows=q.rows,
    iterations=24,outside=1,match={min_steps=1,max_steps=6,min_stretch=.75,max_stretch=1.3,seam_weight=1},
    distortion={min_jacobian=.45,min_stretch=.55,max_stretch=1.6,max_residual=.025}})
  assert(f,why)
  local chart_boundary={}
  local function boundary(i)
    local p=f.grid[i]
    chart_boundary[#chart_boundary+1]={p.x,p.y}
  end
  for i=1,f.width do boundary(i) end
  for j=2,f.height do boundary(j*f.width) end
  for i=f.width-1,1,-1 do boundary((f.height-1)*f.width+i) end
  for j=f.height-1,2,-1 do boundary((j-1)*f.width+1) end
  G.region(chart_boundary,{},G.policy("cm",1),{context=c,max_pair_checks=2000000})
  local seam_mask={}
  for _,seam in ipairs(f.seams) do
    for _,index in ipairs(seam.indices) do seam_mask[index]=true end
  end
  local synthesis=Refine.apply(f,q.library,seam_mask,nil,q.radius)
  local editable,constraints = {},{}
  for i,p in ipairs(f.grid) do
    assert(p.x>=q.bounds[1] and p.x<=q.bounds[3] and p.y>=q.bounds[2] and p.y<=q.bounds[4],
      "deco-chart-outside-document")
    for _,b in ipairs(q.edit) do
      if p.x>=b[1] and p.x<=b[3] and p.y>=b[2] and p.y<=b[4] then
        editable[i]=true
        constraints[i]=b[5]
      end
    end
  end
  assert(#q.edit==0 or next(editable),"deco-empty-edit-mask")
  local refinement=Refine.apply(f,q.library,editable,constraints,q.radius)
  assert(#refinement.unsatisfied==0,"deco-infeasible-edit")
  local contours,area=Vector.contours(f)
  assert(#contours>0 and area.contour_area>0,"deco-empty-output")
  return {id="deco/"..H.value("deco/design",q),definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),
    structures={field={representation="samples",domain={bounds=q.bounds},samples=samples(f)}},
    provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
    extensions={decobrush={request=q,field=f,contours=contours,area=area,synthesis=synthesis,refinement=refinement}}}
end

local function validate(x)
  local e=x.extensions.decobrush
  local contours,proof=Vector.contours(P.plain(e.field))
  assert(P.serialize(contours)==P.serialize(e.contours) and proof.residual<1e-8,"deco-contour-certificate")
  return {ok=true,checks={"Vector boundaries reconstructed from the signed field"}}
end

local function lower(x,v,style)
  local commands=P.array()
  for _,ring in ipairs(x.extensions.decobrush.contours) do
    for i,p in ipairs(ring) do commands[#commands+1]={i==1 and "M" or "L",p[1],p[2]} end
    commands[#commands+1]={"Z"}
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    operations={{op="path",semantic_ref=x.id,commands=commands,transform=P.plain(v.transform),
      paint={fill=P.plain(style.fill or {.10,.17,.24}),fill_rule="nonzero"}}},
    resources=P.array(),clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)}}
end

function M.register(reg)
  local d=M.definition()
  reg:register(d,{validate_inputs=function(s) input(s);return true end,
    generate=function(s,c) return generate(d,s,c) end,validate=validate,lower=lower})
  return d
end

return M
