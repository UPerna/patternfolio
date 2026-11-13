-- Shared vector lowering. Geometry and resource resolution happen once; the
-- serializers below only spell the same plan in PDF and SVG syntax.
local P,B,G,D=require("pattern"),require("pattern_bytes"),require("pattern_geometry"),require("pattern_draw")
local M={VERSION="scene-render-v1"};local identity={1,0,0,1,0,0}
local n=B.pdf_number
local function nums(t)local a={};for _,v in ipairs(t)do a[#a+1]=n(v)end;return table.concat(a," ")end
local function rect(b)return {{"M",b[1],b[2]},{"L",b[3],b[2]},{"L",b[3],b[4]},{"L",b[1],b[4]},{"Z"}}end
local function append(a,b)for _,v in ipairs(b)do a[#a+1]=v end end
local function transformed(commands,m)
  local out={};for _,c in ipairs(commands)do local q={c[1]};for i=2,#c,2 do local p=G.transform({c[i],c[i+1]},m);q[#q+1]=p[1];q[#q+1]=p[2]end;out[#out+1]=q end;return out
end
function M.plan(scene,x,v,d)
  scene=P.scene(P.plain(scene),x,v,d)
  local out={version=M.VERSION,unit="cm",bounds=P.plain(scene.clip.bounds),operations=P.array(),fonts=P.array(),text=P.array(),reading_order=scene.reading_order and P.plain(scene.reading_order) or P.array()}
  local segmented=scene.extensions and scene.extensions.render_profile=="segmented-ops-v1"
  local count,bytes=0,0
  if segmented then out.operation_segments=P.array()end
  local function block()
    if #out.operations==0 then return end
    local data=P.serialize(out.operations);bytes=bytes+#data
    assert(#data<=2*1024*1024 and bytes<=64*1024*1024,"segmented render plan byte budget exceeded")
    out.operation_segments[#out.operation_segments+1]=data;out.operations=P.array()
  end
  local function emit(op)
    out.operations[#out.operations+1]=op
    if segmented then
      count=count+1;assert(count<=100000,"segmented render plan operation budget exceeded")
      if #out.operations==32 then block()end
    end
  end
  local resources,runs={},{}
  for _,r in ipairs(scene.resources)do resources[r.id]=r;if r.kind=="font"then out.fonts[#out.fonts+1]=P.plain(r)end end
  local function clip(commands,rule,m)emit({op="push_clip",commands=transformed(commands,m or identity),fill_rule=rule})end
  clip(rect(out.bounds),"nonzero")
  -- Intersect separate complements: overlapping reservations remove their union.
  for _,r in ipairs(scene.clip.protected_regions)do local c=rect(out.bounds);append(c,rect(r.bounds));clip(c,"evenodd")end
  local function lower(ops,parent,source)
    for _,o in ipairs(ops)do
      local matrix=G.compose(parent,o.transform or identity)
      if o.op=="path"then emit({op="path",commands=P.plain(o.commands),paint=P.plain(o.paint),transform=matrix,semantic_ref=source or o.semantic_ref})
      elseif o.op=="push_clip"then clip(o.commands,o.fill_rule,matrix)
      elseif o.op=="pop_clip"then emit({op="pop_clip"})
      elseif o.op=="symbol"then lower(D.asset(resources[o.resource_ref]).operations,matrix,o.semantic_ref)
      elseif o.op=="text"then
        local font=resources[o.font_ref];local glyphs={};for _,g in ipairs(font.glyphs)do glyphs[g.id]=g end
        for _,p in ipairs(o.glyphs)do
          local k=o.size/font.units_per_em
          local x,y=o.origin[1]+p.offset[1],o.origin[2]+p.offset[2]
          local local_matrix={k,0,0,k,x,y}
          if p.rotation then
            local c,s=math.cos(p.rotation),math.sin(p.rotation)
            local_matrix={c*k,s*k,-s*k,c*k,x,y}
          end
          local gm=G.compose(matrix,local_matrix)
          if #glyphs[p.glyph_ref].commands>0 then emit({op="path",semantic_ref=o.semantic_ref,commands=P.plain(glyphs[p.glyph_ref].commands),paint=P.plain(o.paint),transform=gm})end
        end
        runs[o.semantic_ref]=P.plain(o)
      end
    end
  end
  lower(scene.operations,identity)
  for _=1,1+#scene.clip.protected_regions do emit({op="pop_clip"})end
  for _,id in ipairs(out.reading_order)do assert(runs[id],"missing logical run");out.text[#out.text+1]=runs[id]end
  if segmented then block();out.operations=nil;out.operation_count=count end
  return P.snapshot(out)
end
function M.operations(plan)
  local i,j,total,part=0,0,0,nil
  if plan.operations then return function()i=i+1;return plan.operations[i]end end
  local segments=assert(plan.operation_segments,"missing render plan operations")
  assert(#segments<=3125,"segmented plan block count exceeds profile")
  return function()
    if not part or j==#part then
      i=i+1;if not segments[i]then assert(total==plan.operation_count,"segmented plan count mismatch");return nil end
      part=require("pattern_parse").decode(segments[i]);assert(#part>0 and #part<=32,"invalid segmented plan block");j=0
    end
    j=j+1;total=total+1;return part[j]
  end
end
-- Place fully resolved vector plans in physical page slots. Each panel keeps
-- its own clip scope, including protected regions and internal symbol clips.
function M.compose_vectors(bounds, panels)
  local function valid_box(b)
    assert(#b==4,"expected four page bounds")
    for _,v in ipairs(b) do
      assert(type(v)=="number" and v==v and math.abs(v)<math.huge,"invalid page coordinate")
    end
    assert(b[1]<b[3] and b[2]<b[4],"empty page box")
  end
  valid_box(bounds)
  local out={version=M.VERSION,unit="cm",bounds=P.plain(bounds),operations=P.array(),
    fonts=P.array(),text=P.array(),reading_order=P.array(),operation_segments=P.array(),operation_count=0}
  local bytes=0
  local function flush()
    if #out.operations==0 then return end
    local data=P.serialize(out.operations)
    bytes=bytes+#data
    assert(#data<=2*1024*1024 and bytes<=64*1024*1024,"composition byte budget exceeded")
    out.operation_segments[#out.operation_segments+1]=data
    out.operations=P.array()
  end
  local function emit(op)
    out.operation_count=out.operation_count+1
    assert(out.operation_count<=100000,"composition operation budget exceeded")
    out.operations[#out.operations+1]=op
    if #out.operations==32 then flush() end
  end
  for _,panel in ipairs(panels) do
    local plan,slot=panel.plan,panel.bounds
    valid_box(slot)
    assert(slot[1]>=bounds[1] and slot[2]>=bounds[2] and slot[3]<=bounds[3]
      and slot[4]<=bounds[4],"panel leaves page bounds")
    assert(plan.version==M.VERSION and plan.unit=="cm","incompatible render plan")
    assert(#plan.text==0 and #plan.reading_order==0,"vector composition cannot place logical text")
    local b=plan.bounds
    valid_box(b)
    local width,height=b[3]-b[1],b[4]-b[2]
    local scale=math.min((slot[3]-slot[1])/width,(slot[4]-slot[2])/height)
    local m={scale,0,0,scale,(slot[1]+slot[3]-scale*(b[1]+b[3]))/2,
      (slot[2]+slot[4]-scale*(b[2]+b[4]))/2}
    emit({op="push_clip",commands=rect(slot),fill_rule="nonzero"})
    local depth=0
    for operation in M.operations(plan) do
      local op=P.plain(operation)
      if op.op=="path" then op.transform=G.compose(m,op.transform)
      elseif op.op=="push_clip" then
        op.commands=transformed(op.commands,m)
        depth=depth+1
      elseif op.op=="pop_clip" then
        assert(depth>0,"unbalanced panel clipping")
        depth=depth-1
      else error("unsupported vector composition operation") end
      emit(op)
    end
    assert(depth==0,"unbalanced panel clipping")
    emit({op="pop_clip"})
  end
  flush()
  out.operations=nil
  return P.snapshot(out)
end
local function path(commands,pdf)
  local out={};local names={M="m",L="l",C="c",Z="h"}
  for _,c in ipairs(commands)do local a={};for i=2,#c do a[#a+1]=n(c[i])end
    out[#out+1]=pdf and (table.concat(a," ")..(#a>0 and " " or "")..names[c[1]]) or (c[1]..table.concat(a," "))
  end;return table.concat(out,"\n")
end
local function color(c,gray)
  if gray then c={c[1],c[1],c[1]}end
  return "rgb("..n(c[1]*100).."%,"..n(c[2]*100).."%,"..n(c[3]*100).."%)"
end
function M.svg(plan)
  local b=plan.bounds;local w,h=b[3]-b[1],b[4]-b[2];local defs,out={},{}
  local index,clips=0,{}
  for o in M.operations(plan)do
    if o.op=="push_clip"then
      index=index+1;defs[#defs+1]='<clipPath clipPathUnits="userSpaceOnUse" id="c'..index..'"><path clip-rule="'..o.fill_rule..'" d="'..path(o.commands,false)..'"/></clipPath>'
      clips[#clips+1]=index
    elseif o.op=="pop_clip"then assert(table.remove(clips),"render clip underflow")
    elseif o.op=="path"then
      local p=o.paint
      for _,kind in ipairs({"fill","stroke"})do if p[kind]then
        local attrs={'data-semantic-ref="'..B.xml(o.semantic_ref)..'"','d="'..path(o.commands,false)..'"','transform="matrix('..nums(o.transform)..')"'}
        if kind=="fill"then attrs[#attrs+1]='fill="'..color(p.fill,p.color_space=="gray")..'" fill-rule="'..(p.fill_rule or "nonzero")..'" stroke="none"'
        else
          attrs[#attrs+1]='fill="none" stroke="'..color(p.stroke,p.color_space=="gray")..'" stroke-width="'..n(p.stroke_width)..'" stroke-linecap="'..(p.cap or "butt")..'" stroke-linejoin="'..(p.join or "miter")..'" stroke-miterlimit="'..n(p.miter_limit or 10)..'"'
          if p.dash and #p.dash.array>0 then attrs[#attrs+1]='stroke-dasharray="'..nums(p.dash.array)..'" stroke-dashoffset="'..n(p.dash.phase)..'"'end
        end
        -- Blend the single clipped paint with the actual page backdrop. Keeping
        -- a long-lived clipped ancestor loses that backdrop in Inkscape1.4.2.
        out[#out+1]='<g opacity="'..n(p.opacity or 1)..'" style="mix-blend-mode:'..(p.blend or "normal")..'">'
        for _,clip in ipairs(clips)do out[#out+1]='<g clip-path="url(#c'..clip..')">'end
        out[#out+1]='<path '..table.concat(attrs," ")..'/>'
        for _=1,#clips+1 do out[#out+1]='</g>'end
      end end
    end
  end
  assert(#clips==0,"render clips not balanced")
  local fonts={}
  for i,f in ipairs(plan.fonts)do
    assert(f.variants.opentype,"SVG searchable profile needs embedded OpenType bytes")
    fonts[f.id]={name="SceneFont"..i,font=f}
    defs[#defs+1]='<style>@font-face{font-family:SceneFont'..i..';src:url(data:font/otf;base64,'..f.variants.opentype.content..') format("opentype");}</style>'
  end
  for _,o in ipairs(plan.text)do
    local f=assert(fonts[o.font_ref]);local matrix=o.transform or identity
    if o.glyphs[1].rotation~=nil then
      local visible_parts={}
      local glyphs={}
      for _,g in ipairs(f.font.glyphs)do glyphs[g.id]=g end
      for _,g in ipairs(o.glyphs)do
        visible_parts[#visible_parts+1]='<tspan x="'..n(o.origin[1]+g.offset[1])..'" y="'..
          n(-o.origin[2]-g.offset[2])..'">'..B.xml(glyphs[g.glyph_ref].unicode)..'</tspan>'
      end
      out[#out+1]='<g transform="matrix('..nums(matrix)..')"><text data-semantic-ref="'..B.xml(o.semantic_ref)..
        '" aria-label="'..B.xml(o.text)..'" xml:space="preserve" font-family="'..f.name..'" font-size="'..
        n(o.size)..'" opacity="0" transform="scale(1 -1)">'..table.concat(visible_parts)..'</text></g>'
    else
    out[#out+1]='<g transform="matrix('..nums(matrix)..')"><text data-semantic-ref="'..B.xml(o.semantic_ref)..'" aria-label="'..B.xml(o.text)..'" font-family="'..f.name..'" font-size="'..n(o.size)..'" opacity="0" transform="scale(1 -1)">'
    local glyphs={};for _,g in ipairs(f.font.glyphs)do glyphs[g.id]=g end
    for _,g in ipairs(o.glyphs)do out[#out+1]='<tspan x="'..n(o.origin[1]+g.offset[1])..'" y="'..n(-o.origin[2]-g.offset[2])..'">'..B.xml(glyphs[g.glyph_ref].unicode)..'</tspan>'end
    out[#out+1]='</text></g>'
    end
  end
  return '<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="'..n(w)..'cm" height="'..n(h)..'cm" viewBox="0 0 '..n(w)..' '..n(h)..'" role="img"><defs>'..table.concat(defs,"\n")..'</defs><g transform="translate('..n(-b[1])..' '..n(b[4])..') scale(1 -1)">'..table.concat(out,"\n")..'</g></svg>\n'
end
function M.pdf_document(plans)
  assert(type(plans)=="table" and #plans>=1 and #plans<=4096,"PDF document needs1..4096 shared drawing plans")
  local objects={};local function obj(s)objects[#objects+1]=s;return #objects end
  local function stream(s)return obj('<< /Length '..#s..' >>\nstream\n'..s..'\nendstream')end
  local catalog,pages=obj(false),obj(false);local references={}
  for _,plan in ipairs(plans)do
  local gs,gstates={},{}
  local function state(p)
    local key=n(p.opacity or 1).."/"..(p.blend or "normal")
    if not gs[key]then local name="GS"..(#gstates+1);gs[key]=name;gstates[#gstates+1]='/'..name..' '..obj('<< /Type /ExtGState /ca '..n(p.opacity or 1)..' /CA '..n(p.opacity or 1)..' /BM /'..(p.blend=="multiply" and "Multiply" or "Normal")..' >>')..' 0 R'end
    return '/'..gs[key]..' gs'
  end
  local b=plan.bounds;local k=72/2.54;local content={'q',nums({k,0,0,k,-b[1]*k,-b[2]*k})..' cm'}
  for o in M.operations(plan)do
    if o.op=="push_clip"then append(content,{'q',path(o.commands,true),o.fill_rule=="evenodd" and 'W* n' or 'W n'})
    elseif o.op=="pop_clip"then content[#content+1]='Q'
    elseif o.op=="path"then
      local p=o.paint
      for _,kind in ipairs({"fill","stroke"})do if p[kind]then
        append(content,{'q',nums(o.transform)..' cm',state(p),nums(p[kind])..(p.color_space=="gray" and (kind=="fill" and ' g' or ' G') or (kind=="fill" and ' rg' or ' RG'))})
        if kind=="stroke"then
          append(content,{n(p.stroke_width)..' w',({butt=0,round=1,square=2})[p.cap or "butt"]..' J',({miter=0,round=1,bevel=2})[p.join or "miter"]..' j',n(p.miter_limit or 10)..' M'})
          content[#content+1]=p.dash and ('['..nums(p.dash.array)..'] '..n(p.dash.phase)..' d') or '[] 0 d'
        end
        append(content,{path(o.commands,true),kind=="stroke" and 'S' or p.fill_rule=="evenodd" and 'f*' or 'f','Q'})
      end end
    end
  end
  local fonts,fontrefs={},{}
  for fi,f in ipairs(plan.fonts)do
    local procs,differences,widths,mappings,codes={}, {'1'},{},{},{}
    local box={math.huge,math.huge,-math.huge,-math.huge}
    for i,g in ipairs(f.glyphs)do
      codes[g.id]=i;widths[#widths+1]=n(g.advance);differences[#differences+1]='/g'..i
      local data=n(g.advance)..' 0 '..nums(g.bounds)..' d1\n'..path(g.commands,true)..'\nf'
      procs[#procs+1]='/g'..i..' '..stream(data)..' 0 R';mappings[#mappings+1]=string.format('<%02X> <%s>',i,B.utf16_hex(g.unicode))
      box={math.min(box[1],g.bounds[1]),math.min(box[2],g.bounds[2]),math.max(box[3],g.bounds[3]),math.max(box[4],g.bounds[4])}
    end
    local chunks={};for i=1,#mappings,100 do local batch={};for j=i,math.min(i+99,#mappings)do batch[#batch+1]=mappings[j]end;chunks[#chunks+1]=#batch..' beginbfchar\n'..table.concat(batch,'\n')..'\nendbfchar'end
    local cmap=stream('/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n/CMapName /SceneUnicode def\n/CMapType 2 def\n1 begincodespacerange\n<00> <FF>\nendcodespacerange\n'..table.concat(chunks,'\n')..'\nendcmap\nCMapName currentdict /CMap defineresource pop\nend\nend')
    local font=obj('<< /Type /Font /Subtype /Type3 /Name /F'..fi..' /FontBBox ['..nums(box)..'] /FontMatrix ['..nums({1/f.units_per_em,0,0,1/f.units_per_em,0,0})..'] /CharProcs << '..table.concat(procs,' ')..' >> /Encoding << /Type /Encoding /Differences ['..table.concat(differences,' ')..'] >> /FirstChar 1 /LastChar '..#f.glyphs..' /Widths ['..table.concat(widths,' ')..'] /Resources << >> /ToUnicode '..cmap..' 0 R >>')
    fonts[f.id]={name='F'..fi,codes=codes};fontrefs[#fontrefs+1]='/F'..fi..' '..font..' 0 R'
  end
  -- Visible outlines have already been painted. This ordered, positioned layer
  -- supplies Unicode/search semantics without a system-font substitution.
  for _,o in ipairs(plan.text)do
    -- PDF1.7 section5.2.5: Tr alone does not suppress Type3 painting.
    -- Inherited zero opacity makes the semantic layer invisible in that case.
    local font=assert(fonts[o.font_ref]);append(content,{'q',state({opacity=0}),nums(o.transform or identity)..' cm','/Span << /ActualText <'..B.utf16_hex(o.text,true)..'> >> BDC','BT /'..font.name..' '..n(o.size)..' Tf 3 Tr'})
    if o.glyphs[1].rotation~=nil then
      -- A rotated visual run still has one logical search string. Anchor the
      -- invisible horizontal run at its first glyph to avoid spurious words
      -- from text extractors interpreting every curved placement as a new row.
      local first=o.glyphs[1]
      local encoded={}
      for _,g in ipairs(o.glyphs)do encoded[#encoded+1]=string.format('%02X',font.codes[g.glyph_ref])end
      content[#content+1]=nums({1,0,0,1,o.origin[1]+first.offset[1],o.origin[2]+first.offset[2]})..
        ' Tm <'..table.concat(encoded)..'> Tj'
    else
    for _,g in ipairs(o.glyphs)do content[#content+1]=nums({1,0,0,1,o.origin[1]+g.offset[1],o.origin[2]+g.offset[2]})..' Tm '..string.format('<%02X> Tj',font.codes[g.glyph_ref])end
    end
    append(content,{'ET','EMC','Q'})
  end
  content[#content+1]='Q';local contents=stream(table.concat(content,'\n'))
  local page=obj('<< /Type /Page /Parent '..pages..' 0 R /MediaBox [0 0 '..nums({(b[3]-b[1])*k,(b[4]-b[2])*k})..'] /Resources << /ExtGState << '..table.concat(gstates,' ')..' >> /Font << '..table.concat(fontrefs,' ')..' >> >> /Contents '..contents..' 0 R >>')
  references[#references+1]=page..' 0 R'
  end
  objects[catalog]='<< /Type /Catalog /Pages '..pages..' 0 R >>';objects[pages]='<< /Type /Pages /Kids ['..table.concat(references,' ')..'] /Count '..#references..' >>'
  return require("pdfwriter").encode(objects,catalog)
end
function M.pdf(plan)return M.pdf_document({plan})end
return M
