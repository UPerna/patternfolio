-- Independent mask control: retain actual imported geometry, remove only the L.
local P,Q,V,Parse=require('pattern'),require('pattern_recipe'),require('pattern_render'),require('pattern_parse')
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local recipe=Q.decode(read(arg[1]..'.recipe'))
local d=P.definition(P.plain(recipe.definition));local x=P.instance(Parse.decode(read(arg[1]..'.instance')),d)
local view=Parse.decode(read(arg[2]..'.view'));local scene=Parse.decode(read(arg[2]..'.scene'))
view=P.plain(P.view(view,x,d));scene=P.plain(P.scene(scene,x,P.view(view,x,d),d))
local keep=P.array();local removed=0
local requested=view.extensions.tex_document.geometry.reservations
assert(#requested==2,'Expected the two captured callout reservations')
local targets={};for _,bounds in ipairs(requested)do targets[P.serialize(bounds)]=true end
for _,r in ipairs(view.protected_regions)do
  if targets[P.serialize(r.bounds)]then removed=removed+1 else keep[#keep+1]=r end
end
assert(removed==2,'Expected exactly the two measured callout reservations')
view.extensions={diagnostic={operation='remove-two-callout-masks',source_view=view.id,removed_regions=removed}}
view.id=view.id..'/mask-control';view.protected_regions=keep
view=P.view(view,x,d);scene.id=view.id..'/scene';scene.view_ref=view.id
scene.clip={bounds=P.plain(view.crop),protected_regions=P.plain(keep)}
scene=P.scene(scene,x,view,d)
local f=assert(io.open(arg[3],'wb'));f:write(V.pdf(V.plan(scene,x,view,d)));f:close()
print('Mask control retained source instance and every original drawing operation')
