-- Shared paint-only output treatment. No topology, paths, clips or dimensions change.
local P,H,Parse,D=require('pattern'),require('pattern_hash'),require('pattern_parse'),require('pattern_draw')
local M={VERSION='output-paint-v1'}
local function keys(t,allowed)
 local yes={};for k in allowed:gmatch('%S+')do yes[k]=true end
 for k in pairs(t)do assert(yes[k],'output profile unknown field:'..tostring(k))end
end
function M.split(style)
 local family=P.plain(style);local profile=family.output_profile;family.output_profile=nil
 if not profile then return family,nil end
 assert(type(profile)=='table'and profile.schema_version==1,'output profile schema_version1 required')
 keys(profile,'schema_version mode fill stroke')
 assert(profile.mode=='source'or profile.mode=='monochrome'or profile.mode=='palette','unsupported output profile mode')
 if profile.mode=='palette'then
  for _,name in ipairs{'fill','stroke'}do
   local c=profile[name];assert(type(c)=='table'and #c==3,'palette requires fill/stroke RGB triples')
   for k,v in pairs(c)do assert(type(k)=='number'and k%1==0 and k>=1 and k<=3 and type(v)=='number'and v==v and v>=0 and v<=1,'palette RGB outside0..1')end
  end
 else assert(profile.fill==nil and profile.stroke==nil,'colors require palette mode')end
 return family,profile
end
local function tone(c,space)
 -- Same encoded-RGB weights and three-decimal neutral precision as ink.lua.
 local v=space=='gray'and c[1]or .2126*c[1]+.7152*c[2]+.0722*c[3]
 return assert(tonumber((string.format('%.3f',v):gsub(',','.'))))
end
function M.apply(scene,profile,context)
 if not profile or profile.mode=='source'then return scene end
 local out=P.plain(scene)
 local function paint(p)
  local original=p.color_space or 'rgb'
  for _,name in ipairs{'fill','stroke'}do if p[name]then
   local g=tone(p[name],original)
   if profile.mode=='monochrome'then p[name]={g}
   else local c=profile[name];p[name]={(1-g)*c[1]+g,(1-g)*c[2]+g,(1-g)*c[3]+g}end
  end end
  p.color_space=profile.mode=='monochrome'and'gray'or'rgb';D.validate_paint(p)
  if context then context:consume('operations',1)end
 end
 local function operations(list)
  for _,op in ipairs(list)do if op.op=='path'or op.op=='text'then paint(op.paint)end end
 end
 operations(out.operations)
 for _,resource in ipairs(out.resources)do if resource.kind=='symbol'then
  local asset=D.asset(resource);operations(asset.operations)
  local content=P.serialize(asset);assert(#content<=2*1024*1024,'styled vector resource exceeds bounded profile')
  resource.variants.scene={encoding='utf8',content=content,sha256=H.sha256(content)}
 end end
 out.extensions=out.extensions or{};out.extensions.output_profile=P.plain(profile)
 return out
end
return M
