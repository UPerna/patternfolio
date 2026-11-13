-- Backend-neutral drawing grammar shared by scenes and reusable vector assets.
local P,Bytes,H=require("pattern"),require("pattern_bytes"),require("pattern_hash")
local M={VERSION="drawing-grammar-v1"}
local function need(ok,why)assert(ok,"drawing: "..why)end
local function fields(t,names,label)
  need(type(t)=="table",label.." object required");local known={};for key in names:gmatch('%S+')do known[key]=true end
  for key in pairs(t)do need(known[key],label.." unknown key "..tostring(key))end
end
local function finite(n)return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function seq(t,label)
  need(type(t)=="table",label.." array required");local n=#t
  for k in pairs(t)do need(type(k)=="number" and k%1==0 and k>=1 and k<=n,label.." must be dense")end
  for i=1,n do need(t[i]~=nil,label.." must be dense")end
  return t
end
local function numbers(t,n,label)seq(t,label);need(#t==n,label.." wrong arity");for _,v in ipairs(t)do need(finite(v),label.." finite values required")end end
local function bounds(t,label,positive)numbers(t,4,label);need(positive and t[3]>t[1] and t[4]>t[2] or not positive and t[3]>=t[1] and t[4]>=t[2],label.." invalid bounds")end
local function matrix(t,label)
  numbers(t,6,label);local determinant=t[1]*t[4]-t[2]*t[3]
  need(finite(determinant) and determinant~=0,label.." singular/nonfinite transform")
end
local function commands(list,allow_empty)
  seq(list,"commands");local current,drawn=false,false
  for _,c in ipairs(list)do
    seq(c,"command");local sizes={M=3,L=3,C=7,Z=1};need(sizes[c[1]]==#c,"unsupported path command/arity")
    for i=2,#c do need(finite(c[i]),"nonfinite path coordinate")end
    if c[1]=="M" then current=true else need(current,"path must begin with M");if c[1]~="Z" then drawn=true end end
  end
  need(allow_empty and #list==0 or drawn,"path has no drawn segment")
end
local function rule(v)need(v=="nonzero" or v=="evenodd","unsupported winding rule")end
local function paint(p)
  fields(p,"fill stroke stroke_width color_space opacity blend fill_rule cap join miter_limit dash","paint")
  need(p.fill or p.stroke,"actual fill/stroke required")
  local cs=p.color_space or "rgb";need(cs=="rgb" or cs=="gray","unsupported paint color space")
  for _,k in ipairs({"fill","stroke"})do if p[k]then numbers(p[k],cs=="gray" and 1 or 3,"paint."..k);for _,v in ipairs(p[k])do need(v>=0 and v<=1,"color outside [0,1]")end end end
  if p.opacity~=nil then need(finite(p.opacity) and p.opacity>=0 and p.opacity<=1,"opacity outside [0,1]")end
  if p.blend~=nil then need(p.blend=="normal" or p.blend=="multiply","unsupported blend")end
  if p.fill_rule then rule(p.fill_rule)end
  if p.stroke then
    need(finite(p.stroke_width) and p.stroke_width>0,"positive physical stroke width required; device hairlines unsupported")
    local cap,join=p.cap or "butt",p.join or "miter"
    need(cap=="butt" or cap=="round" or cap=="square","unsupported cap");need(join=="miter" or join=="round" or join=="bevel","unsupported join")
    if p.miter_limit~=nil then need(finite(p.miter_limit) and p.miter_limit>=1,"invalid miter limit")end
    if p.dash then
      fields(p.dash,"array phase","dash");seq(p.dash.array,"dash.array");local sum=0
      for _,v in ipairs(p.dash.array)do need(finite(v) and v>=0,"invalid dash length");sum=sum+v end
      need(#p.dash.array==0 or sum>0,"dash array is allzero");need(finite(p.dash.phase) and p.dash.phase>=0,"invalid dash phase")
    end
  else need(p.stroke_width==nil and p.cap==nil and p.join==nil and p.miter_limit==nil and p.dash==nil,"stroke controls require a stroke")end
end
local validate_ops
local function resources(list)
  local map={};seq(list,"resources")
  for _,r in ipairs(list)do
    fields(r,"id kind unit bounds variants provenance profile glyphs units_per_em family license font_sha256","resource")
    need(type(r.id)=="string" and #r.id>0 and not map[r.id],"unique resource ID required");map[r.id]=r
    need(r.kind=="symbol" or r.kind=="font","unsupported resource kind")
    need(type(r.variants)=="table" and next(r.variants),"actual resource variants required")
    for format,variant in pairs(r.variants)do
      need(format=="scene" or format=="pdf" or format=="svg" or format=="opentype","unsupported resource variant")
      fields(variant,"encoding content media_type graphics_states sha256","resource variant")
      need(type(variant.content)=="string" and #variant.content>0,"actual resource bytes required")
      need(variant.encoding=="utf8" or variant.encoding=="base64","explicit resource encoding required")
      local data=variant.encoding=="base64" and Bytes.base64_decode(variant.content) or variant.content
      if variant.sha256 then need(H.is_digest(variant.sha256) and H.sha256(data)==variant.sha256,"resource byte digest mismatch")end
    end
    if r.kind=="symbol" then
      need(r.unit=="cm" or r.unit=="bp","explicit symbol unit required");bounds(r.bounds,"symbol.bounds",true)
      if r.variants.scene then
        need(r.variants.scene.encoding=="utf8","neutral asset must use UTF-8 JSON")
        local asset=require("pattern_parse").decode(r.variants.scene.content)
        fields(asset,"kind schema_version unit operations","vector asset")
        need(asset.kind=="vector_asset" and asset.schema_version==1 and asset.unit==r.unit,"vector asset schema/unit mismatch")
        validate_ops(asset.operations,{},nil,nil,true)
      end
    else
      need(r.profile=="positioned-outlines-v1","font requires explicit positioned-outline profile; opaque fonts need migration")
      need(finite(r.units_per_em) and r.units_per_em>=16 and r.units_per_em<=1000000,"invalid font units-per-em")
      seq(r.glyphs,"font.glyphs");need(#r.glyphs>0 and #r.glyphs<=255,"font profile needs1..255 glyphs per resource")
      need(type(r.family)=="string" and #r.family>0 and type(r.license)=="string" and #r.license>0,"font attribution/license required")
      local glyphs={}
      for _,g in ipairs(r.glyphs)do
        fields(g,"id unicode advance bounds commands","glyph")
        need(type(g.id)=="string" and #g.id>0 and not glyphs[g.id],"unique glyph ID required");glyphs[g.id]=g
        need(type(g.unicode)=="string" and #g.unicode>0,"glyph Unicode cluster required")
        need(finite(g.advance) and g.advance>=0,"invalid glyph advance");bounds(g.bounds,"glyph.bounds",false);commands(g.commands,true)
      end
      if r.variants.opentype then
        local v=r.variants.opentype;need(v.encoding=="base64","embedded font must use base64")
        local data=Bytes.base64_decode(v.content);local magic=data:sub(1,4)
        need(magic=="OTTO" or magic=="\0\1\0\0","unsupported embedded font container")
        need(H.is_digest(r.font_sha256) and H.sha256(data)==r.font_sha256,"embedded font SHA256 required/mismatched")
      end
    end
  end
  return map
end
validate_ops=function(ops,map,ids,text,asset)
  seq(ops,"operations");need(#ops>0 and #ops<=100000,"nonempty bounded operations required")
  local depth,text_runs=0,{}
  for _,op in ipairs(ops)do
    need(type(op)=="table","operation object required")
    if op.semantic_ref~=nil then need(asset or ids and ids[op.semantic_ref],"missing semantic source")end
    if op.op=="path" then
      fields(op,"op semantic_ref commands paint transform","path operation");need(asset or op.semantic_ref,"path semantic source required")
      commands(op.commands,false);paint(op.paint);if op.transform then matrix(op.transform,"path.transform")end
    elseif op.op=="push_clip" then
      fields(op,"op semantic_ref commands fill_rule transform","clip operation");commands(op.commands,false);rule(op.fill_rule)
      if op.transform then matrix(op.transform,"clip.transform")end;depth=depth+1
    elseif op.op=="pop_clip" then fields(op,"op","clip pop");depth=depth-1;need(depth>=0,"clip stack underflow")
    elseif op.op=="symbol" then
      need(not asset,"nested resource references require an explicit future profile")
      fields(op,"op semantic_ref resource_ref transform","symbol operation");need(ids and ids[op.semantic_ref] and map[op.resource_ref] and map[op.resource_ref].kind=="symbol","missing symbol resource/source");matrix(op.transform,"symbol.transform")
    elseif op.op=="text" then
      need(not asset,"text belongs to semantic scene runs")
      fields(op,"op semantic_ref font_ref text origin size glyphs paint transform","text operation")
      local font=map[op.font_ref];need(font and font.kind=="font" and text,"font resource/text semantics required")
      local run;for _,r in ipairs(text.runs)do if r.id==op.semantic_ref then run=r end end
      need(run and run.text==op.text and #op.text>0 and not text_runs[op.semantic_ref],"text differs from semantic run or is duplicated/empty");text_runs[op.semantic_ref]=true
      numbers(op.origin,2,"text.origin");need(finite(op.size) and op.size>0,"positive text size in cm required")
      paint(op.paint);need(op.paint.fill and not op.paint.stroke,"text profile uses filled glyph outlines")
      if op.transform then matrix(op.transform,"text.transform")end
      local glyphs={};for _,g in ipairs(font.glyphs)do glyphs[g.id]=g end
      seq(op.glyphs,"positioned glyphs");need(#op.glyphs>0,"actual positioned glyphs required")
      local content={}
      for _,g in ipairs(op.glyphs)do
        fields(g,"glyph_ref offset rotation","positioned glyph")
        need(glyphs[g.glyph_ref],"missing glyph");numbers(g.offset,2,"glyph.offset")
        if g.rotation~=nil then need(finite(g.rotation) and math.abs(g.rotation)<=math.pi,"glyph rotation must be finite radians")end
        content[#content+1]=glyphs[g.glyph_ref].unicode
      end
      need(table.concat(content)==op.text,"glyph clusters differ from Unicode content")
    else error("drawing: unsupported operation "..tostring(op.op),0)end
  end
  need(depth==0,"unbalanced clip stack")
  if text then for _,run in ipairs(text.runs)do need(text_runs[run.id],"semantic text run missing from lowering")end end
end
function M.validate_scene(scene,ids,text)
  local map=resources(scene.resources);validate_ops(scene.operations,map,ids,text,false)
  if text then need(P.serialize(scene.reading_order)==P.serialize(text.reading_order),"reading order differs from instance")
  else need(scene.reading_order==nil,"reading order requires text semantics")end
  return true
end
function M.asset(resource)
  resource=P.plain(resource)
  resources({resource});need(resource.variants.scene,"neutral vector variant required by this backend")
  return require("pattern_parse").decode(resource.variants.scene.content)
end
M.validate_commands=commands;M.validate_paint=paint
return M
