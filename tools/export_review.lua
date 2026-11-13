-- Read retained CLI bundles; diagnostics annotate actual lowered path endpoints.
-- They are export diagnostics, never a substitute for family topology witnesses.
local P,V,H,Parse,G=require('pattern'),require('pattern_render'),require('pattern_hash'),require('pattern_parse'),require('pattern_geometry')
local root=assert(arg[1],'retained batch directory required')
local function read(p)local f=assert(io.open(p,'rb'));local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(p,'wb'));f:write(s);f:close();return H.sha256(s)end
local catalog=Parse.decode(read('examples/cli/catalog.json'));local batch=Parse.decode(read(root..'/batch.json'));local rows=P.array()
for _,row in ipairs(catalog.examples)do
 local folder=root..'/'..assert(batch.items[row.id].output)
 local q=require('pattern_recipe').decode(read(folder..'/recipe.json'));local d=q.definition
 local x
 local transport=io.open(folder..'/instance-format.json','rb')
 if transport then
  transport:close()
  x=require('pattern_botanical_legacy').decode_bundle(read(folder..'/instance.json'),function(sha)return read(folder..'/block-'..sha..'.json')end,d)
 else x=Parse.instance(read(folder..'/instance.json'))end
 local view=Parse.decode(read(folder..'/view.json'));local scene=Parse.instance(read(folder..'/scene.json'))
 local plan=V.plan(scene,x,view,d);local b=plan.bounds;local scale=math.min(b[3]-b[1],b[4]-b[2]);local marks=P.array();local count=0
 for op in V.operations(plan)do if op.op=='path'then count=count+1 end end
 local limit=64;local stride=math.max(1,math.ceil(count/limit));local index=0
 for op in V.operations(plan)do if op.op=='path'then
  index=index+1
  if (index-1)%stride==0 then
   local c=op.commands[#op.commands];if c[1]=='Z'then c=op.commands[#op.commands-1]end
   if #c>=3 then local p=G.transform({c[#c-1],c[#c]},op.transform);local r=scale*.003
    marks[#marks+1]={op='path',semantic_ref=x.id,commands={{'M',p[1]-r,p[2]},{'L',p[1]+r,p[2]},{'M',p[1],p[2]-r},{'L',p[1],p[2]+r}},paint={stroke={.85,.05,.3},stroke_width=scale*.001,cap='round'}}
   end
  end
 end end
 local hashes={};local diagnostics=P.plain(scene)
 for _,op in ipairs(marks)do diagnostics.operations[#diagnostics.operations+1]=op end
 diagnostics=P.scene(diagnostics,x,view,d)
 local mono=require('pattern_output_style').apply(scene,{schema_version=1,mode='monochrome'})
 local variants={diagnostic=V.plan(diagnostics,x,view,d),monochrome=V.plan(mono,x,view,d)}
 for name,p in pairs(variants)do for _,format in ipairs{'pdf','svg'}do
  local path=name..'.'..format;hashes[path]=write(folder..'/'..path,V[format](p))
 end end
 -- An intentionally narrow quarter-window through existing paths; no regeneration.
 local crop={b[1]+.375*(b[3]-b[1]),b[2]+.375*(b[4]-b[2]),b[1]+.625*(b[3]-b[1]),b[2]+.625*(b[4]-b[2])}
 local cv=P.plain(view);cv.crop=crop
 local cs=P.plain(scene);cs.clip.bounds=crop
 hashes['crop.svg']=write(folder..'/crop.svg',V.svg(V.plan(cs,x,cv,d)))
 rows[#rows+1]={id=row.id,folder=batch.items[row.id].output,recipe_sha256=H.sha256(read(folder..'/recipe.json')),instance_sha256=H.sha256(read(folder..'/instance.json')),scene_sha256=H.sha256(read(folder..'/scene.json')),path_count=count,endpoint_marks=#marks,diagnostic_limit=limit,diagnostic_stride=stride,outputs=hashes,crop=crop,protected_regions=P.plain(view.protected_regions)}
 print('Export review variants',row.id,count,#marks)
end
write(root..'/export-review.json',P.serialize({schema_version=1,status='structural_variants_passed_visual_pending',runtime=_VERSION,scope='Original clean bundles; validated monochrome paint-only scene; bounded actual projected endpoint overlay; narrow crop. Overlay is not a family topology certificate.',profiles=rows}))
