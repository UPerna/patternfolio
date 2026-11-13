-- Validated physical document input, shared with the Design Specification.
-- This is context for the five contracts, not a second pattern representation.
local P=require("pattern")
local M={VERSION="document-context-v1"}
local documents=setmetatable({},{__mode="k"})
local function need(ok,why)assert(ok,"document: "..why)end
local function finite(x)return type(x)=="number" and x==x and math.abs(x)<math.huge end
local function fields(t,names,label)
  need(type(t)=="table",label.." object required");local map={};for k in names:gmatch('%S+')do map[k]=true end
  for k in pairs(t)do need(map[k],label.." unknown key "..tostring(k))end
end
local function array(t,label)
  need(type(t)=="table",label.." array required");for k in pairs(t)do need(type(k)=="number" and k%1==0 and k>=1 and k<=#t,label.." must be dense")end
  for i=1,#t do need(t[i]~=nil,label.." must be dense")end
  if #t==0 then setmetatable(t,{__jsontype="array"})end;return t
end
local function tuple(t,n,label,nonnegative)
  array(t,label);need(#t==n,label.." arity");for _,v in ipairs(t)do need(finite(v) and (not nonnegative or v>=0),label.." invalid dimension")end
end
local function id(s,label)need(type(s)=="string" and #s>0,label.." ID required")end
local function box(b,label)tuple(b,4,label);need(b[3]>b[1] and b[4]>b[2],label.." positive bounds required")end
local function inside(a,b)return a[1]>=b[1] and a[2]>=b[2] and a[3]<=b[3] and a[4]<=b[4]end
local function shifted(b,x,y)return {b[1]+x,b[2]+y,b[3]+x,b[4]+y}end
function M.new(input)
  local t=P.plain(input);fields(t,"id unit frame twoside pages spreads","context");id(t.id,"document");need(t.unit=="cm","physical document unit must be cm")
  fields(t.frame,"id origin","frame");id(t.frame.id,"frame");tuple(t.frame.origin,2,"frame.origin")
  need(type(t.twoside)=="boolean","explicit twoside flag required");array(t.pages,"pages");need(#t.pages>0 and #t.pages<=4096,"document needs1..4096 pages/panels")
  local ids,numbers={},{}
  for _,p in ipairs(t.pages)do
    fields(p,"id number size origin trim bleed margins binding_offset offset protected_regions anchors legacy_host","page")
    id(p.id,"page");need(not ids[p.id],"duplicate page ID");ids[p.id]=p
    need(finite(p.number) and p.number%1==0 and p.number>=1 and not numbers[p.number],"unique positive page number required");numbers[p.number]=true
    tuple(p.size,2,"page.size");need(p.size[1]>0 and p.size[2]>0,"positive media size required");tuple(p.origin,2,"page.origin")
    local media={0,0,p.size[1],p.size[2]};p.trim=p.trim or media;box(p.trim,"page.trim");need(inside(p.trim,media),"trim exceeds media")
    p.bleed=p.bleed or {0,0,0,0};tuple(p.bleed,4,"page.bleed",true)
    p.bleed_bounds={p.trim[1]-p.bleed[1],p.trim[2]-p.bleed[2],p.trim[3]+p.bleed[3],p.trim[4]+p.bleed[4]};need(inside(p.bleed_bounds,media),"bleed exceeds physical media")
    p.margins=p.margins or {0,0,0,0};tuple(p.margins,4,"page.margins",true)
    p.binding_offset=p.binding_offset or 0;need(finite(p.binding_offset) and p.binding_offset>=0,"invalid binding offset")
    p.offset=p.offset or {0,0};tuple(p.offset,2,"page.offset")
    p.recto=not t.twoside or p.number%2==1;p.inner_side=p.recto and "left" or "right"
    p.content={p.trim[1]+p.margins[1],p.trim[2]+p.margins[2],p.trim[3]-p.margins[3],p.trim[4]-p.margins[4]}
    if p.recto then p.content[1]=p.content[1]+p.binding_offset else p.content[3]=p.content[3]-p.binding_offset end
    p.content=shifted(p.content,p.offset[1],p.offset[2]);box(p.content,"margins/binding/offset content")
    p.content_within_trim=inside(p.content,p.trim)
    if p.legacy_host then
      fields(p.legacy_host,"dimensions_sp settings","legacy host snapshot")
      need(p.binding_offset==0 and p.offset[1]==0 and p.offset[2]==0,"legacy binding and offsets are already resolved in host dimensions; do not apply twice")
      local g=M.legacy_geometry(p.legacy_host.dimensions_sp,p.number,t.twoside,p.legacy_host.settings).geometry
      local expected={g.actual_left,g.ybot,g.actual_right,g.ytop}
      need(math.abs(p.size[1]-g.pw)<1e-10 and math.abs(p.size[2]-g.ph)<1e-10,"legacy document media differs from actual host dimensions")
      for i=1,4 do need(math.abs(p.content[i]-expected[i])<1e-10,"legacy document content differs from actual host offsets/margins")end
    end
    p.protected_regions=p.protected_regions or P.array();array(p.protected_regions,"protected_regions")
    local reservations={}
    for _,r in ipairs(p.protected_regions)do
      fields(r,"id bounds space role","reservation");id(r.id,"reservation");need(not reservations[r.id],"duplicate reservation ID");reservations[r.id]=true;box(r.bounds,"reservation.bounds")
      need(r.space=="page" or r.space=="content","reservation needs explicit page/content coordinate space")
      need(r.role=="protected_content","reservation role must be protected_content")
      if r.space=="content"then r.bounds=shifted(r.bounds,p.content[1],p.content[2])end;r.space="page"
    end
    p.anchors=p.anchors or P.array();array(p.anchors,"anchors");local anchors={}
    for _,a in ipairs(p.anchors)do
      fields(a,"id role point space","anchor");id(a.id,"anchor");need(not anchors[a.id],"duplicate anchor ID");anchors[a.id]=true;id(a.role,"anchor role");tuple(a.point,2,"anchor.point")
      need(a.space=="world" or a.space=="page" or a.space=="content","explicit anchor space required")
      if a.space=="content"then a.point={a.point[1]+p.content[1],a.point[2]+p.content[2]};a.space="page"end
      if a.space=="page"then a.point={a.point[1]+p.origin[1],a.point[2]+p.origin[2]};a.space="world"end
    end
    p.world_bounds=shifted(media,p.origin[1],p.origin[2]);p.world_content=shifted(p.content,p.origin[1],p.origin[2])
  end
  t.spreads=t.spreads or P.array();array(t.spreads,"spreads");local spreads,used={},{}
  for _,s in ipairs(t.spreads)do
    fields(s,"id left right gutter","spread");id(s.id,"spread");need(not spreads[s.id],"duplicate spread ID");spreads[s.id]=true
    local l,r=ids[s.left],ids[s.right];need(t.twoside and l and r and l~=r,"spread needs two distinct known facing pages")
    need(l.number%2==0 and r.number==l.number+1,"spread needs even verso followed by odd recto")
    need(not used[l.id] and not used[r.id],"page belongs to multiple spreads");used[l.id],used[r.id]=true,true
    need(finite(s.gutter) and s.gutter>=0,"nonnegative explicit gutter required")
    need(math.abs(l.origin[1]+l.size[1]+s.gutter-r.origin[1])<=1e-9 and l.origin[2]==r.origin[2],"spread page origins do not match media widths/gutter")
  end
  t.kind="document_context";t.schema_version=1;local result=P.snapshot(t);documents[result]=true;return result
end
function M.import(data)
  local t=P.plain(data);need(t.kind=="document_context" and t.schema_version==1,"unsupported document schema")
  fields(t,"kind schema_version id unit frame twoside pages spreads","imported context")
  t.kind,t.schema_version=nil,nil
  for _,p in ipairs(array(t.pages,"pages"))do
    fields(p,"id number size origin trim bleed margins binding_offset offset protected_regions anchors legacy_host bleed_bounds recto inner_side content content_within_trim world_bounds world_content","imported page")
    for _,key in ipairs({"bleed_bounds","recto","inner_side","content","content_within_trim","world_bounds","world_content"})do p[key]=nil end
  end
  local result=M.new(t);need(P.serialize(result)==P.serialize(data),"imported derived page metadata differs from recomputed physical context")
  return result
end
function M.page(document,id)
  need(documents[document],"validated document context required; use import after deserialization")
  for _,p in ipairs(document.pages)do if p.id==id then return p end end;error("document: unknown page "..tostring(id),0)
end
function M.masks(page)
  local out=P.array();for _,r in ipairs(page.protected_regions)do out[#out+1]={bounds=P.plain(r.bounds),role="protected_content"}end;return out
end
-- Actual host dimensions in scaled TeX points, not invented equivalents. The
-- legacy function remains the authority for overhang, parity and offsets.
function M.legacy_geometry(dimensions_sp,page,twoside,options,reservations)
  need(type(dimensions_sp)=="table" and finite(page) and page>=1 and page%1==0 and type(twoside)=="boolean","legacy host snapshot required")
  local keys={};for name in ("paperwidth paperheight oddsidemargin evensidemargin hoffset voffset topmargin headheight headsep textwidth textheight footskip"):gmatch('%S+')do
    keys[name]=true;local v=dimensions_sp[name];need(finite(v) and v%1==0 and math.abs(v)<=1073741823,"missing/out-of-range integer scaled-point host dimension "..name)
  end
  for name in pairs(dimensions_sp)do need(keys[name],"unknown host dimension "..tostring(name))end
  for _,name in ipairs({"paperwidth","paperheight","textwidth","textheight"})do need(dimensions_sp[name]>0,"positive host dimension required: "..name)end
  local settings=require("layout").resolve(P.plain(options or {}));local F=require("florilegium")
  local saved={dimen=F.dimen,page=F.page,twoside=F.twoside}
  F.dimen=function(name)return assert(dimensions_sp[name],"missing host dimension")end;F.page=function()return page end;F.twoside=twoside
  local ok,g=pcall(F.geometry,settings.text_gap,settings.side)
  F.dimen,F.page,F.twoside=saved.dimen,saved.page,saved.twoside;need(ok,tostring(g))
  need(g.colright>=1.8,"text-gap leaves less than18mm for the grown garden; reduce text-gap or increase the selected margin")
  g.layout=settings;g.reserves=P.array()
  for _,r in ipairs(reservations or {})do box(r,"legacy physical reservation");g.reserves[#g.reserves+1]=g.mirror and {g.pw-r[3],r[2],g.pw-r[1],r[4]} or P.plain(r)end
  return P.snapshot({geometry=g,settings=settings,canonical_to_page=g.mirror and {-1,0,0,1,g.pw,0} or {1,0,0,1,0,0},
    unit="cm",density_semantics="legacy spacing/branch/detail control, not ink area percentage",text_orientation="native text unchanged; botanical labels counter-reflect in folio.lua",source="existing florilegium.geometry and layout.resolve; no formula rewrite"})
end
function M.from_legacy_host(input)
  local t=P.plain(input);fields(t,"id frame twoside pages spreads","legacy document input");array(t.pages,"legacy pages")
  local pages=P.array()
  for _,p in ipairs(t.pages)do
    fields(p,"id number origin dimensions_sp options protected_regions anchors","legacy page input")
    local resolved=M.legacy_geometry(p.dimensions_sp,p.number,t.twoside,p.options)
    local g=resolved.geometry
    pages[#pages+1]={id=p.id,number=p.number,origin=p.origin,size={g.pw,g.ph},margins={g.actual_left,g.ybot,g.pw-g.actual_right,g.ph-g.ytop},
      binding_offset=0,offset={0,0},protected_regions=p.protected_regions or P.array(),anchors=p.anchors or P.array(),
      legacy_host={dimensions_sp=p.dimensions_sp,settings=P.plain(resolved.settings)}}
  end
  return M.new({id=t.id,unit="cm",frame=t.frame,twoside=t.twoside,pages=pages,spreads=t.spreads or P.array()})
end
function M.legacy_page(document,page_id)
  local p=M.page(document,page_id);need(p.legacy_host,"page has no actual legacy host snapshot")
  local reservations={};for _,r in ipairs(p.protected_regions)do reservations[#reservations+1]=P.plain(r.bounds)end
  return M.legacy_geometry(p.legacy_host.dimensions_sp,p.number,document.twoside,p.legacy_host.settings,reservations)
end
M.shift_box=shifted
return M
