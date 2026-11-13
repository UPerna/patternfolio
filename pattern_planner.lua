-- Document planning separates immutable constructions from their page views.
local P,D,G,N,H=require("pattern"),require("pattern_document"),require("pattern_geometry"),require("pattern_predicates"),require("pattern_hash")
local M={VERSION="document-planner-v1"};local profiles=setmetatable({},{__mode="k"})
local function need(ok,message)assert(ok,"planner: "..message)end
local function fail(code,message,details)error({code=code,message=message,details=details},0)end
local function attempt(fn,context)
  local ok,value=pcall(fn);if ok then return value end
  local code=type(value)=="table" and value.code or "invalid_plan"
  return nil,P.snapshot({status=code=="cancelled" and "cancelled" or "rejected",code=code,diagnostics={type(value)=="table" and value.message or tostring(value)},details=type(value)=="table" and value.details or nil,budgets=context and context:receipt() or nil})
end
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function fields(t,names,label)
  need(type(t)=="table",label.." object required");local known={};for key in names:gmatch('%S+')do known[key]=true end
  for key in pairs(t)do need(known[key],label.." unknown key "..tostring(key))end
end
local function ids(list)local map={};for _,id in ipairs(list)do map[id]=true end;return map end
local function sorted(map)local out=P.array();for id in pairs(map)do out[#out+1]=id end;table.sort(out,P.byte_less);return out end
local function box(b)
  need(type(b)=="table" and #b==4,"crop bounds required");for k,v in pairs(b)do need(type(k)=="number" and k%1==0 and k>=1 and k<=4 and finite(v),"finite dense crop bounds required")end
  need(b[3]>b[1] and b[4]>b[2],"positive crop required");return P.plain(b)
end
local function rect(b)return {{b[1],b[2]},{b[3],b[2]},{b[3],b[4]},{b[1],b[4]}}end
local function in_box(p,b)return p[1]>=b[1] and p[2]>=b[2] and p[1]<=b[3] and p[2]<=b[4]end
local function intersects(a,b)return a[1]<=b[3] and a[3]>=b[1] and a[2]<=b[4] and a[4]>=b[2]end
local function union(a,b)return a and {math.min(a[1],b[1]),math.min(a[2],b[2]),math.max(a[3],b[3]),math.max(a[4],b[4])} or P.plain(b)end
local function expand(b,r)return {b[1]-r,b[2]-r,b[3]+r,b[4]+r}end
local function point_inside(polygon,p)
  local winding=0
  for i,a in ipairs(polygon)do local b=polygon[i%#polygon+1];local sign=N.orient2d(a,b,p)
    if sign==0 and p[1]>=math.min(a[1],b[1]) and p[1]<=math.max(a[1],b[1]) and p[2]>=math.min(a[2],b[2]) and p[2]<=math.max(a[2],b[2])then return true end
    if a[2]<=p[2] and b[2]>p[2] and sign>0 then winding=winding+1 elseif a[2]>p[2] and b[2]<=p[2] and sign<0 then winding=winding-1 end
  end;return winding~=0
end
local function polygon_intersects(polygon,b,policy)
  for _,p in ipairs(polygon)do if in_box(p,b)then return true end end
  local corners=rect(b);for _,p in ipairs(corners)do if point_inside(polygon,p)then return true end end
  for i,a in ipairs(polygon)do for j,c in ipairs(corners)do local hit=G.segment_intersection(a,polygon[i%#polygon+1],c,corners[j%4+1],policy)
    if hit.kind=="unresolved"then fail("view_classification_unresolved","polygon/crop intersection exceeds numerical policy")end
    if hit.kind~="none"then return true end
  end end;return false
end
-- Sign(n/d-bound) is an exact determinant sign of the admitted binary64 bound
-- and exact integer numerator/denominator. No rounded render point assigns IDs.
function M.compare_coordinate(vertex,axis,bound)
  need(finite(bound) and (axis==1 or axis==2),"finite coordinate comparison required")
  if vertex.exact then local r=vertex.exact.components[axis];return -N.orient2d({0,0},{r[2],r[1]},{1,bound})end
  local value=vertex.point[axis];return value>bound and 1 or value<bound and -1 or 0
end
local function vertex_inside(v,b)
  return M.compare_coordinate(v,1,b[1])>=0 and M.compare_coordinate(v,2,b[2])>=0 and M.compare_coordinate(v,1,b[3])<=0 and M.compare_coordinate(v,2,b[4])<=0
end
function M.profile(definition,options)
  local d=P.definition(P.plain(definition));local p=P.plain(options)
  need(d.units=="cm","planner profile1 requires cm construction units; convert explicitly before planning")
  fields(p,"mode construction_scale maximum_tile_diameter density_parameter focal_parameter routing generation_region","planning profile")
  need(p.mode=="fixed_frame" or p.mode=="adaptive" or p.mode=="view_only","explicit planning mode required")
  if p.mode=="adaptive"then need(p.generation_region=="content" or p.generation_region=="media" or p.generation_region=="trim" or p.generation_region=="bleed","adaptive family must declare its permitted generation region")
  else need(p.generation_region==nil,"generation-region control belongs to an adaptive profile")end
  local tags=ids(d.capabilities)
  need(p.mode~="fixed_frame" or tags.tiling,"fixed-frame tile planning requires tiling semantics")
  G.policy("cm",p.construction_scale)
  if p.mode=="fixed_frame"then need(finite(p.maximum_tile_diameter) and p.maximum_tile_diameter>0,"fixed-frame profile requires a verified tile-diameter bound")
  else need(p.maximum_tile_diameter==nil,"tile halo control requires fixed-frame tiling")end
  for _,name in ipairs({"density_parameter","focal_parameter"})do if p[name]~=nil then
    need(type(p[name])=="string" and #p[name]>0,"intent parameter reference must be a string")
    local parameter=d.parameters[p[name]];need(p.mode=="adaptive" and parameter and (parameter.type=="number" or parameter.type=="integer"),"intent must map to a declared numeric generator parameter")
  end end
  need(not(p.density_parameter and p.density_parameter==p.focal_parameter),"density and focal intents cannot alias the same parameter")
  p.routing=p.routing or false;need(type(p.routing)=="boolean" and (not p.routing or p.mode=="adaptive"),"routing capability requires adaptive mode")
  p.definition_ref={id=d.id,version=d.version};p.structural_avoidance="view_masks_only_unless_generator_separately_validates"
  local snapshot=P.snapshot(p);profiles[snapshot]=true;return snapshot
end
function M.import_profile(d,data)
  local p=P.plain(data);need(p.definition_ref.id==d.id and p.definition_ref.version==d.version,"profile definition mismatch")
  p.definition_ref,p.structural_avoidance=nil,nil;local result=M.profile(d,p)
  need(P.serialize(result)==P.serialize(data),"planning profile metadata mismatch");return result
end
local function profile(d,p)
  need(profiles[p] and p.definition_ref.id==d.id and p.definition_ref.version==d.version,"validated matching planning profile required")
end
local function page_crop(page,options)
  fields(options,"crop region tile_policy halo require_continuation minimum_stroke minimum_text_size","view options")
  need(not(options.crop and options.region),"choose a crop or a named physical region")
  local regions={media={0,0,page.size[1],page.size[2]},trim=page.trim,bleed=page.bleed_bounds,content=page.content}
  local crop=options.crop and box(options.crop) or P.plain(assert(regions[options.region or "media"],"unknown page region"))
  need(crop[1]>=0 and crop[2]>=0 and crop[3]<=page.size[1] and crop[4]<=page.size[2],"view crop exceeds physical media")
  for _,name in ipairs({"minimum_stroke","minimum_text_size"})do if options[name]~=nil then need(finite(options[name]) and options[name]>0,"positive minimum dimension required")end end
  return crop
end
function M.prepare_specification(d,specification,document,capability,intent,page_id)
  return attempt(function()
    profile(d,capability);local s=P.plain(P.specification(P.plain(specification),d));intent=P.plain(intent or {})
    fields(intent,"density focal_count","generation intent")
    for name,parameter in pairs({density=capability.density_parameter,focal_count=capability.focal_parameter})do if intent[name]~=nil then s.parameters[parameter]=intent[name]end end
    if intent.density~=nil and not capability.density_parameter or intent.focal_count~=nil and not capability.focal_parameter then fail("unsupported_intent","family does not declare the requested density/focal generator parameter")end
    local bounds,masks,anchors=nil,P.array(),P.array();local mode=capability.mode
    if mode=="view_only"then fail("generation_not_supported","view-only profile does not generate geometry")end
    if mode=="fixed_frame"then
      need(page_id==nil,"fixed-frame generation is planned once for the whole document, not per page")
      for _,page in ipairs(document.pages)do D.page(document,page.id);bounds=union(bounds,page.world_bounds)end
      bounds=expand(bounds,capability.maximum_tile_diameter)
    else
      local page=D.page(document,page_id)
      local regions={media={0,0,page.size[1],page.size[2]},content=page.content,trim=page.trim,bleed=page.bleed_bounds}
      bounds=D.shift_box(regions[capability.generation_region],page.origin[1],page.origin[2]);anchors=P.plain(page.anchors)
      for _,r in ipairs(page.protected_regions)do masks[#masks+1]={bounds=D.shift_box(r.bounds,page.origin[1],page.origin[2]),role="protected_content"}end
    end
    s.document={unit="cm",bounds=bounds,protected_regions=masks}
    s.extensions=s.extensions or {};s.extensions.planning_generation={schema_version=1,mode=mode,frame=P.plain(document.frame),profile=P.plain(capability)}
    if mode=="adaptive"then
      s.extensions.planning_generation.document={id=document.id,twoside=document.twoside}
      s.extensions.planning_generation.page=P.plain(D.page(document,page_id))
    end
    s=P.specification(s,d)
    return P.snapshot({status="requires_generator_and_validation",mode=mode,specification=P.plain(s),document_ref=document.id,document_digest=H.sha256(P.serialize(document)),page_ref=page_id,generation_region=capability.generation_region,
      frame=P.plain(document.frame),anchors=anchors,halo=mode=="fixed_frame" and capability.maximum_tile_diameter or 0,
      decisions={mode=="fixed_frame" and "one fixed world construction; reservations remain view masks" or "document-aware adaptive request; generator must validate actual adaptation", "density/focal controls retain declared generator meanings"}})
  end)
end
local function recipe_template(document,page_id,capability,options)
  local page=D.page(document,page_id);options=P.plain(options or {});local crop=page_crop(page,options)
  return {unit="cm",transform={1,0,0,1,-page.origin[1],-page.origin[2]},crop=crop,protected_regions=D.masks(page),derived=false,validity="construction_preserved",
    extensions={document_planning={schema_version=1,document=P.plain(document),profile=P.plain(capability),page_id=page_id,options=options}}}
end
local function recipe_design(d,s,document,capability,intent,page_id)
  if capability.mode~="view_only"then
    local generation_page;if capability.mode~="fixed_frame"then generation_page=page_id end
    local request,diagnostic=M.prepare_specification(d,s,document,capability,intent,generation_page)
    if not request then fail(diagnostic.code,table.concat(P.plain(diagnostic.diagnostics),"; "))end
    return request.specification
  end
  need(next(P.plain(intent or {}))==nil,"view-only recipe cannot consume generation intent")
  local data=P.plain(P.specification(P.plain(s),d));data.extensions=data.extensions or {}
  data.extensions.planning_generation={schema_version=1,mode="view_only",frame=P.plain(document.frame),profile=P.plain(capability)}
  return P.specification(data,d)
end
-- The recipe stores validated planning inputs, not selections tied to an old
-- instance. Replay re-runs view planning against the newly validated instance.
function M.recipe(d,s,document,page_id,capability,intent,options)
  return attempt(function()
    profile(d,capability);local design=recipe_design(d,s,document,capability,intent,page_id)
    return require("pattern_recipe").from_specification(d,design,recipe_template(document,page_id,capability,options),2)
  end)
end
function M.recipe_view_inputs(d,s,view,dimension)
  need(dimension==2,"document recipe profile1 requires2D construction")
  fields(view.extensions,"document_planning","recipe view extensions")
  local input=view.extensions.document_planning
  fields(input,"schema_version document profile page_id options","document recipe inputs");need(input.schema_version==1,"unsupported document planning recipe version")
  local document=D.import(input.document);local capability=M.import_profile(d,input.profile);local page=D.page(document,input.page_id)
  local template=recipe_template(document,input.page_id,capability,input.options)
  need(P.serialize(template)==P.serialize(view),"recipe physical view disagrees with its document planning inputs")
  local expected=recipe_design(d,s,document,capability,{},input.page_id)
  need(P.serialize(expected)==P.serialize(s),"recipe generation context disagrees with its document/frame/anchors")
  return {document=document,profile=capability,page_id=page.id,options=P.snapshot(P.plain(input.options))}
end
local function selection(x,crop,masks,p,options,context)
  local t=x.structures.tiling;local vertices,points,errors,edges,incidence,cell_records={},{},{},{},{},{}
  local policy=G.policy("cm",p.construction_scale);local conversion=P.array()
  need(#t.cells<=10000 and #t.edges<=20000,"view selection budget exceeded")
  for _,v in ipairs(t.vertices)do local point,receipt=G.render_vertex(v);vertices[v.id]=v;points[v.id]=point;errors[v.id]=receipt.absolute_error_bounds;if v.exact then conversion[#conversion+1]={vertex=v.id,receipt=receipt}end end
  for _,e in ipairs(t.edges)do edges[e.id]=e;incidence[e.id]=P.array()end
  local selected,selected_edges={},{}
  local tile_policy=options.tile_policy or "clipped_tiles";need(tile_policy=="clipped_tiles" or tile_policy=="full_tiles","unsupported tile view policy")
  for _,cell in ipairs(t.cells)do
    if context then context:consume("objects",1)end
    local polygon,contained,bounds,rounding={},true,nil,0
    for _,use in ipairs(cell.boundary)do local edge=edges[use.edge];local id=use.reversed and edge.to or edge.from;local v=vertices[id];local point=points[id]
      local error=errors[id];rounding=math.max(rounding,error[1],error[2])
      polygon[#polygon+1]=point;contained=contained and vertex_inside(v,crop);bounds=union(bounds,{point[1]-error[1],point[2]-error[2],point[1]+error[1],point[2]+error[2]});incidence[edge.id][#incidence[edge.id]+1]=cell.id
    end
    local diagonal=math.sqrt((bounds[3]-bounds[1])^2+(bounds[4]-bounds[2])^2)
    if diagonal>p.maximum_tile_diameter*(1+1e-12)then fail("tile_bound_exceeded","cell "..cell.id.." exceeds the declared conservative tile-diameter bound")end
    local keep=tile_policy=="full_tiles" and contained or tile_policy=="clipped_tiles" and intersects(bounds,crop)
    if keep and tile_policy=="full_tiles"then for _,mask in ipairs(masks)do local guarded=expand(mask,rounding);if intersects(bounds,guarded) and polygon_intersects(polygon,guarded,policy)then keep=false;break end end end
    if keep then selected[cell.id]=true;for _,use in ipairs(cell.boundary)do selected_edges[use.edge]=true end end
    cell_records[#cell_records+1]={id=cell.id,polygon=polygon,bounds=bounds}
  end
  local halo=options.halo or p.maximum_tile_diameter
  need(finite(halo) and halo>=p.maximum_tile_diameter,"generation halo must cover the declared tile-diameter bound")
  local query=expand(crop,halo);local query_region=G.region(rect(query),{},policy)
  local crop_region=G.region(rect(crop),{},policy);local patch,view_boundary,cuts,masked=P.array(),P.array(),P.array(),P.array()
  local mask_regions={};for _,b in ipairs(masks)do mask_regions[#mask_regions+1]=G.region(rect(b),{},policy)end
  local continuation=true
  for _,edge in ipairs(t.edges)do
    if context then context:consume("operations",1)end
    local uses=incidence[edge.id];local count=0;for _,id in ipairs(uses)do if selected[id]then count=count+1 end end
    if #uses==1 then
      patch[#patch+1]=edge.id
      local hit=G.clip_segment(query_region,points[edge.from],points[edge.to],policy)
      if hit.status~="complete"then fail("halo_classification_unresolved","source boundary near halo cannot be classified")end
      if not hit.empty then continuation=false end
    elseif count==1 then view_boundary[#view_boundary+1]=edge.id end
    if selected_edges[edge.id]then
      local hit=G.clip_segment(crop_region,points[edge.from],points[edge.to],policy)
      if hit.status~="complete"then fail("view_classification_unresolved","source edge near crop cannot be classified")end
      local complete=#hit.segments==1 and hit.segments[1].parameters[1]==0 and hit.segments[1].parameters[2]==1
      if not complete and not hit.empty then cuts[#cuts+1]={edge=edge.id,kind="view_cut_not_topological_boundary",segments=P.plain(hit.segments),contacts=P.plain(hit.contacts)}end
      for i,region in ipairs(mask_regions)do local mask=G.clip_segment(region,points[edge.from],points[edge.to],policy)
        if mask.status~="complete"then fail("mask_classification_unresolved","edge near reservation cannot be classified")end
        if not mask.empty then masked[#masked+1]={edge=edge.id,mask_index=i,kind="protected_view_mask_not_topological_boundary",segments=P.plain(mask.segments),contacts=P.plain(mask.contacts)}end
      end
    end
  end
  local center={(query[1]+query[3])/2,(query[2]+query[4])/2};local covered=false
  for _,c in ipairs(cell_records)do if in_box(center,c.bounds) and point_inside(c.polygon,center)then covered=true;break end end
  continuation=continuation and covered
  if options.require_continuation and not continuation then fail("insufficient_patch_halo","existing patch does not establish continuation through the requested generation halo; generate a larger validated patch in the same world frame",{requested_bounds=query,frame=x.frame.id})end
  if not next(selected)then fail("empty_view_selection","no cells satisfy the requested tile/crop/mask policy")end
  return {policy=tile_policy,cell_ids=sorted(selected),edge_ids=sorted(selected_edges),true_patch_boundaries=patch,selection_boundaries=view_boundary,
    cut_edges=cuts,masked_edges=masked,halo=halo,requested_generation_bounds=query,continuation_established=continuation,
    coverage_assumption="family structurally validated its planar nonoverlapping patch; no source boundary in halo and center covered",coordinate_conversions=conversion}
end
local function graph_trace(x,crop,masks,capability,context)
  if not x.structures.graph then return nil end
  local g=x.structures.graph;need(#g.edges<=20000 and #g.vertices<=40000,"graph view trace budget exceeded")
  local points,degree={},{};for _,v in ipairs(g.vertices)do points[v.id]=G.render_vertex(v);degree[v.id]=0 end
  local policy=G.policy("cm",capability.construction_scale);local region=G.region(rect(crop),{},policy)
  local cuts,masked=P.array(),P.array();local regions={};for _,b in ipairs(masks)do regions[#regions+1]=G.region(rect(b),{},policy)end
  for _,e in ipairs(g.edges)do
    if context then context:consume("operations",1)end
    degree[e.from],degree[e.to]=degree[e.from]+1,degree[e.to]+1
    local hit=G.clip_segment(region,points[e.from],points[e.to],policy)
    if hit.status~="complete"then fail("graph_view_unresolved","straight source edge cannot be classified at the crop")end
    local complete=#hit.segments==1 and hit.segments[1].parameters[1]==0 and hit.segments[1].parameters[2]==1
    if not complete and not hit.empty then cuts[#cuts+1]={edge=e.id,kind="view_cut_not_topological_endpoint",segments=P.plain(hit.segments),contacts=P.plain(hit.contacts)}end
    for i,mask in ipairs(regions)do local h=G.clip_segment(mask,points[e.from],points[e.to],policy);if h.status~="complete"then fail("graph_mask_unresolved","straight edge too near mask boundary")end
      if not h.empty then masked[#masked+1]={edge=e.id,mask_index=i,segments=P.plain(h.segments)}end
    end
  end
  local ends={};for id,n in pairs(degree)do if n==1 then ends[id]=true end end
  return {geometry_scope="straight semantic endpoint segments; curved drawing paths are not inferred",source_endpoints=sorted(ends),cut_edges=cuts,masked_edges=masked,topology_unchanged=true}
end
function M.view(instance,d,document,page_id,capability,options,context)
  return attempt(function()
    profile(d,capability);local x=P.instance(P.plain(instance),d);local before=P.serialize(x);local page=D.page(document,page_id)
    need(x.frame.dimension==2 and x.frame.unit=="cm","planner profile1 needs a2D construction frame in cm")
    need(x.frame.id==document.frame.id and P.serialize(x.frame.origin)==P.serialize(document.frame.origin),"construction/document world frames differ")
    options=P.plain(options or {});local crop=page_crop(page,options)
    if options.require_continuation~=nil then need(type(options.require_continuation)=="boolean","continuation policy must be boolean")end
    local world_crop=D.shift_box(crop,page.origin[1],page.origin[2]);local masks=P.array()
    for _,r in ipairs(page.protected_regions)do masks[#masks+1]=D.shift_box(r.bounds,page.origin[1],page.origin[2])end
    local chosen
    if capability.mode=="fixed_frame"then chosen=selection(x,world_crop,masks,capability,options,context)
    else need(options.tile_policy==nil and options.halo==nil and not options.require_continuation,"tile continuation controls require a fixed-frame tiling profile")end
    local strand_topology=P.array();if x.structures.strands then for _,s in ipairs(x.structures.strands.components)do strand_topology[#strand_topology+1]={id=s.id,closed=s.closed,endpoints=P.plain(s.endpoints),view_clip_is_not_a_break=true}end end
    local metadata={planner=M.VERSION,document_ref=document.id,page_ref=page.id,page_number=page.number,recto=page.recto,origin_world=P.plain(page.origin),media_size=P.plain(page.size),trim=P.plain(page.trim),bleed=P.plain(page.bleed_bounds),content=P.plain(page.content),anchors=P.plain(page.anchors),selection=chosen,strand_topology=strand_topology,
      graph_trace=graph_trace(x,world_crop,masks,capability,context),topology_unchanged=true,reservations="view_masks_not_topology_repairs",requirements={minimum_stroke=options.minimum_stroke,minimum_text_size=options.minimum_text_size}}
    local v=P.view({id=x.id.."/document/"..document.id.."/page/"..page.id,instance_ref=x.id,unit="cm",transform={1,0,0,1,-page.origin[1],-page.origin[2]},crop=crop,
      protected_regions=D.masks(page),derived=false,validity="construction_preserved",extensions={document=metadata}},x,d)
    need(P.serialize(x)==before,"view mutated construction")
    return P.snapshot({status="planned",view=P.plain(v),source_digest=H.sha256(before),document_digest=H.sha256(P.serialize(document)),profile=P.plain(capability),decisions=metadata})
  end,context)
end
local function minimum_scale(m)
  if m[2]==0 and m[3]==0 then return math.min(math.abs(m[1]),math.abs(m[4])),0 end
  if m[1]==0 and m[4]==0 then return math.min(math.abs(m[2]),math.abs(m[3])),0 end
  -- Reject cancellation-sensitive affine measurements using the established
  -- conditioning policy. The general square-root formula also retains a
  -- conservative rounding guard; an unresolved threshold never becomes a pass.
  G.inverse(m,G.policy("cm",1))
  local scale=math.max(math.abs(m[1]),math.abs(m[2]),math.abs(m[3]),math.abs(m[4]));need(scale>0,"singular paint transform")
  local a,b,c,d=m[1]/scale,m[2]/scale,m[3]/scale,m[4]/scale;local det=a*d-b*c;local trace=a*a+b*b+c*c+d*d
  local maximum=math.sqrt((trace+math.sqrt(math.max(0,trace*trace-4*det*det)))/2)
  return math.abs(det)/maximum*scale,64*math.sqrt(2^-52)*scale*math.sqrt(trace)
end
function M.check_render_requirements(rendered,requirements)
  fields(requirements,"minimum_stroke minimum_text_size","render requirements")
  for _,name in ipairs({"minimum_stroke","minimum_text_size"})do
    need(requirements[name]==nil or finite(requirements[name]) and requirements[name]>0,"positive finite print minimum required")
  end
  local report={status="passed",stroke_scope="explicit stroke paints; filled-feature thickness is not certified"}
  if requirements.minimum_stroke or requirements.minimum_text_size then
    need(rendered and rendered.version==require("pattern_render").VERSION,"compatible render plan required");local minimum,minimum_lower,minimum_upper=math.huge,math.huge,math.huge
    for o in require("pattern_render").operations(rendered)do if o.op=="path" and o.paint.stroke and (o.paint.opacity or 1)>0 then
      local scale,error=minimum_scale(o.transform);minimum=math.min(minimum,o.paint.stroke_width*scale);minimum_lower=math.min(minimum_lower,o.paint.stroke_width*math.max(0,scale-error));minimum_upper=math.min(minimum_upper,o.paint.stroke_width*(scale+error))
    end end
    if minimum<math.huge then report.minimum_stroke=minimum end
    if requirements.minimum_stroke and minimum==math.huge then fail("stroke_evidence_missing","scene has no explicit strokes; this profile cannot certify filled-feature thickness")end
    if requirements.minimum_stroke and minimum_upper<requirements.minimum_stroke then fail("minimum_stroke_unsatisfied","actual transformed stroke is below the requested physical minimum")end
    if minimum_lower<math.huge then report.minimum_stroke_lower_bound=minimum_lower end
    if minimum_upper<math.huge then report.minimum_stroke_upper_bound=minimum_upper end
    if requirements.minimum_stroke and minimum_lower<requirements.minimum_stroke then fail("minimum_stroke_unresolved","stroke minimum falls inside the affine rounding guard")end
    local text,text_lower,text_upper=math.huge,math.huge,math.huge;for _,o in ipairs(rendered.text)do local scale,error=minimum_scale(o.transform or {1,0,0,1,0,0});text=math.min(text,o.size*scale);text_lower=math.min(text_lower,o.size*math.max(0,scale-error));text_upper=math.min(text_upper,o.size*(scale+error))end
    if text<math.huge then report.minimum_text_size=text end
    if requirements.minimum_text_size and text==math.huge then fail("text_evidence_missing","scene has no positioned text to establish the requested minimum")end
    if requirements.minimum_text_size and text_upper<requirements.minimum_text_size then fail("minimum_text_size_unsatisfied","actual transformed text size is below the requested physical minimum")end
    if text_lower<math.huge then report.minimum_text_size_lower_bound=text_lower end
    if text_upper<math.huge then report.minimum_text_size_upper_bound=text_upper end
    if requirements.minimum_text_size and text_lower<requirements.minimum_text_size then fail("minimum_text_size_unresolved","text minimum falls inside the affine rounding guard")end
  end
  return P.snapshot(report)
end
function M.lower(registry,id,instance,d,planned,style,context)
  return attempt(function()
    need(planned.status=="planned" and H.sha256(P.serialize(instance))==planned.source_digest,"plan refers to different instance bytes")
    local v=P.view(P.plain(planned.view),instance,d);local scene=registry:lower(id,instance,v,style,context)
    local choice=planned.decisions.selection
    if choice then
      local keep=ids(choice.cell_ids);for _,id in ipairs(choice.edge_ids)do keep[id]=true end
      local known={};for _,c in ipairs(instance.structures.tiling.cells)do known[c.id]=true end;for _,e in ipairs(instance.structures.tiling.edges)do known[e.id]=true end
      local s=P.plain(scene);local ops=P.array()
      for _,o in ipairs(s.operations)do
        if o.op=="push_clip" or o.op=="pop_clip"then ops[#ops+1]=o
        else need(known[o.semantic_ref],"tile-aware lowering requires separate cell/global-edge semantic references; ambiguous grouped paint is unsupported");if keep[o.semantic_ref]then ops[#ops+1]=o end end
      end
      s.operations=ops;scene=P.scene(s,instance,v,d)
    end
    local requirements=planned.decisions.requirements
    local rendered
    if requirements.minimum_stroke or requirements.minimum_text_size then rendered=require("pattern_render").plan(scene,instance,v,d)end
    local report=M.check_render_requirements(rendered,requirements)
    return P.snapshot({status="lowered",scene=P.plain(scene),view=P.plain(v),validation=report,source_digest=planned.source_digest,decisions=P.plain(planned.decisions)})
  end,context)
end
function M.route(capability,request,context)
  return attempt(function()
    need(profiles[capability] and capability.routing,"family does not declare document routing")
    local r=P.plain(request);fields(r,"unit frame points regions exclusions clearance","route request")
    need(r.unit=="cm" and type(r.frame)=="string" and #r.frame>0,"route needs explicit cm frame")
    need(type(r.points)=="table" and #r.points>=2 and #r.points<=4096,"route needs2..4096 points")
    for _,p in ipairs(r.points)do G.point(p)end
    need(type(r.regions)=="table" and #r.regions>=1 and #r.regions<=64,"route needs1..64 permitted rectangles")
    need(type(r.exclusions)=="table" and #r.exclusions<=256,"bounded exclusions required")
    need(finite(r.clearance) and r.clearance>=0,"explicit nonnegative route clearance required")
    local policy=G.policy("cm",capability.construction_scale);local regions={}
    for _,b in ipairs(r.regions)do regions[#regions+1]=G.region(rect(box(b)),{},policy)end
    for _,b in ipairs(r.exclusions)do box(b)end
    local original=P.plain(r.points);local points,found=require("space").route(r.points,r.regions,r.exclusions,r.clearance)
    local details={original_points=original,frame=r.frame,conclusion="bounded search failure, not a universal nonexistence proof"}
    if not found then fail("continuous_route_not_found","no route was found around the reservations; original sampled path is preserved in evidence",details)end
    if not require("space").path_clear(points,r.exclusions,r.clearance)then fail("route_clearance_unsatisfied","candidate does not meet the requested full-segment obstacle clearance",details)end
    need(P.serialize(points[1])==P.serialize(original[1]) and P.serialize(points[#points])==P.serialize(original[#original]),"routing moved source endpoints")
    local drawn=0
    for i=2,#points do
      if context then context:consume("operations",1)end
      local a,b=points[i-1],points[i]
      if a[1]~=b[1] or a[2]~=b[2]then
        drawn=drawn+1
        local intervals={}
        for _,region in ipairs(regions)do local hit=G.clip_segment(region,a,b,policy)
          if hit.status~="complete"then fail("route_containment_unresolved","candidate is too near a permitted-region boundary to certify",details)end
          for _,s in ipairs(hit.segments)do intervals[#intervals+1]=s.parameters end
        end
        table.sort(intervals,function(x,y)return x[1]<y[1] or x[1]==y[1] and x[2]<y[2]end)
        local reach=0
        for _,t in ipairs(intervals)do if t[1]>reach then break end;reach=math.max(reach,t[2])end
        if reach<1 then fail("route_outside_permitted_region","candidate leaves the union of permitted rectangles; no sampled-point acceptance",details)end
      end
    end
    if drawn==0 then fail("degenerate_route","route contains no nonzero segment",details)end
    return P.snapshot({status="routed",unit="cm",frame=r.frame,points=points,clearance=r.clearance,validation={status="passed",checks={"source endpoints retained","whole-segment obstacle clearance","whole-segment coverage by permitted rectangle union"}}})
  end,context)
end
return M
