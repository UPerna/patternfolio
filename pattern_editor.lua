-- Typed editor intent -> canonical recipe using the actual document planner.
local P,Q,H,D,Planner=require('pattern'),require('pattern_recipe'),require('pattern_hash'),require('pattern_document'),require('pattern_planner')
local M={VERSION='recipe-edit-v1'}
local function fields(t)
 local allowed={schema_version=true,parameters=true,seed=true,inputs=true,style=true,crop=true,protected_regions=true,page_size=true}
 for key in pairs(t)do assert(allowed[key],'recipe edit unknown field:'..tostring(key))end
end
local function merge(target,patch)
 assert(type(patch)=='table','recipe edit requires an object')
 for key,value in pairs(patch)do assert(type(key)=='string','recipe edit named fields required');target[key]=P.plain(value)end
end
local function document_input(document)
 local t=P.plain(D.import(document));t.kind=nil;t.schema_version=nil
 for _,page in ipairs(t.pages)do for _,key in ipairs{'bleed_bounds','recto','inner_side','content','content_within_trim','world_bounds','world_content'}do page[key]=nil end end
 return t
end
function M.apply(recipe,edit)
 local previous=Q.new(recipe);local q=P.plain(previous);edit=P.plain(edit)
 assert(type(edit)=='table'and getmetatable(edit).__jsontype=='object','recipe edit must be an object')
 assert(edit.schema_version==1,'recipe edit schema_version1 required');fields(edit)
 for _,key in ipairs{'parameters','inputs','style'}do
  if edit[key]~=nil then assert(type(edit[key])=='table'and getmetatable(edit[key]).__jsontype=='object','recipe edit '..key..' requires an object')end
 end
 for _,key in ipairs{'crop','protected_regions','page_size'}do
  if edit[key]~=nil then assert(type(edit[key])=='table'and getmetatable(edit[key]).__jsontype=='array','recipe edit '..key..' requires an array')end
 end
 if edit.parameters then merge(q.design.parameters,edit.parameters)end
 if edit.inputs then merge(q.design.inputs,edit.inputs)end
 if edit.style then merge(q.design.style,edit.style)end
 if edit.seed~=nil then
  q.design.seed=edit.seed
  if q.definition.id=='botanical/legacy-authored'or q.definition.id=='botanical/legacy-grown'then
   -- The legacy generator consumes this validated native host packet. Keep
   -- its seed synchronized with the edited design; never reuse old growth.
   local geometry=assert(q.design.extensions and q.design.extensions.legacy_geometry,'Floral seed editing requires actual native host geometry')
   geometry.seed=edit.seed
  end
 end
 if edit.page_size then
  assert(type(edit.page_size)=='table'and #edit.page_size==2,'page size needs width/height in cm')
  for _,n in ipairs(edit.page_size)do assert(type(n)=='number'and n==n and n>=.1 and n<=60,'editor media size must be0.1..60cm')end
 end
 local planned=q.view.extensions and q.view.extensions.document_planning
 if planned then
  local input=document_input(planned.document);local page
  for _,p in ipairs(input.pages)do if p.id==planned.page_id then page=p end end;assert(page,'editor physical page missing')
  local options=P.plain(planned.options)
  if edit.page_size then page.size=P.plain(edit.page_size);page.trim={0,0,page.size[1],page.size[2]};options.crop={0,0,page.size[1],page.size[2]};options.region=nil end
  if edit.protected_regions then
   page.protected_regions=P.array()
   for i,region in ipairs(edit.protected_regions)do page.protected_regions[i]={id='editor-region-'..i,bounds=P.plain(region.bounds),space='page',role='protected_content'}end
  end
  if edit.crop then options.crop=P.plain(edit.crop);options.region=nil end
  local document=D.new(input);local capability=Planner.import_profile(q.definition,planned.profile)
  local next_recipe,problem=Planner.recipe(q.definition,q.design,document,planned.page_id,capability,{},options)
  assert(next_recipe,problem and table.concat(P.plain(problem.diagnostics),'; '))
  local data=P.plain(next_recipe);data.id=q.id;data.dependencies=P.plain(q.dependencies);q=data
 else
  if edit.page_size then
   local b=q.design.document.bounds;local c=q.view.crop
   q.design.document.bounds={b[1],b[2],b[1]+edit.page_size[1],b[2]+edit.page_size[2]}
   q.view.crop={c[1],c[2],c[1]+edit.page_size[1],c[2]+edit.page_size[2]}
  end
  if edit.crop then q.view.crop=P.plain(edit.crop)end
  if edit.protected_regions then q.view.protected_regions=P.plain(edit.protected_regions)end
 end
 local result=Q.new(q)
 return result,{schema_version=1,operation=M.VERSION,input_recipe_sha256=H.sha256(Q.encode(previous)),
  output_recipe_sha256=H.sha256(Q.encode(result)),edit_sha256=H.value('recipe/edit',edit),
  structural_change=Q.structural_digest(previous)~=Q.structural_digest(result)}
end
return M
