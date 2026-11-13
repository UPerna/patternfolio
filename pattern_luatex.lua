-- Trusted LuaLaTeX host. Recipes remain bounded data; no subprocess is used.
local P,H,V=require('pattern'),require('pattern_hash'),require('pattern_render')
local B=require('pattern_bytes')
local F=require('florilegium');local M={};local CM=2.54/(72.27*65536)
local core,source,root;local bindings={};local declarations=P.array();local pages=P.array();local inline=P.array()
local started,shipped=false,0;local pending
local function need(ok,why)assert(ok,'florilegium patterns: '..why)end
local function read(path,limit)
  local file=assert(io.open(path,'rb'),'florilegium patterns: file not found '..path)
  local bytes=file:read((limit or 2*1024*1024)+1);file:close()
  need(bytes and #bytes<=(limit or 2*1024*1024),'input exceeds byte limit: '..path);return bytes
end
local function resolve(path)
  need(type(path)=='string' and #path>0 and not path:find('%z'),'invalid input filename')
  local file=io.open(path,'rb');if file then file:close();return path end
  local found=kpse.find_file(path)
  need(found,'input not found '..path)
  return found
end
local function source_bytes()
  local lfs=require('lfs');root=root or assert(kpse.find_file('pattern.lua','lua')):gsub('[^/\\]+$','')
  local files={}
  for name in lfs.dir(root)do
    if name:match('%.lua$') or name:match('^florilegium.*%.sty$') or name:match('^florilegium.*%.def$')then
      files[name]=read(root..name,16*1024*1024)
    end
  end
  return files
end
local function init()
  if not core then
    source=source_bytes()
    core=require('pattern_tex').new({source=source,runtime='LuaLaTeX/'..tostring(status.luatex_version)..'/'..tostring(status.luatex_revision)})
  end
  return core
end
local function write_new(path,bytes)
  local old=io.open(path,'rb')
  if old then local existing=old:read('*a');old:close();need(existing==bytes,'existing generated filename has different bytes: '..path);return end
  local file=assert(io.open(path,'wb'));assert(file:write(bytes));assert(file:close())
end
local function persist(key,files)
  local prefix='florilegium-pattern-'..key
  local hashes={}
  for suffix,bytes in pairs(files)do
    local path=prefix..'.'..suffix;write_new(path,bytes);hashes[suffix]=H.sha256(bytes)
  end
  return prefix,hashes
end
local function instance_files(asset)
  local files={recipe=asset.recipe_bytes,record=P.serialize(asset.result.record),view=P.serialize(asset.result.view),scene=asset.result.bytes.scene}
  if asset.result.instance.extensions.legacy then
    local manifest,blocks=require('pattern_botanical_legacy').encode_bundle(asset.result.instance)
    files.instance=manifest
    for hash,bytes in pairs(blocks)do files['block-'..hash..'.json']=bytes end
  else files.instance=asset.result.bytes.instance end
  return files
end
function M.input(name,path)
  need(shipped==0,'declare dependency files before the first shipped page')
  need(type(name)=='string' and #name>0 and not bindings[name],'duplicate or empty dependency name')
  bindings[name]=read(resolve(path))
end
function M.declare(name,path)
  need(shipped==0,'declare recipes before the first shipped page')
  local bytes=read(resolve(path));local q=require('pattern_recipe').decode(bytes);local inputs={}
  for _,group in pairs(q.dependencies)do for key in pairs(group)do inputs[key]=assert(bindings[key],'florilegium patterns: bind dependency '..key..' before declaring this recipe')end end
  local asset=init():declare(name,bytes,inputs);local prefix,hashes=persist(asset.key,instance_files(asset))
  declarations[#declarations+1]={name=name,family=asset.definition.id,prefix=prefix,hashes=hashes,
    instance_sha256=asset.instance_sha256,generation_record=asset.result.record.id}
end
function M.begin_document()started=true end
function M.use(name,width)
  need(started,'inline patterns require the document body')
  need(type(width)=='number' and width>=0,'inline width must be nonnegative')
  local plan,asset,physical=init():inline(name,width*CM)
  local pdf=V.pdf(plan);local key=H.value('tex/inline',{source=asset.environment.source.digest,pdf=H.sha256(pdf)})
  local prefix,hashes=persist(key,{pdf=pdf})
  local size=width>0 and ('[width='..B.pdf_number(width*CM)..'cm]') or ''
  local actual_width,actual_height=physical.width,physical.height
  inline[#inline+1]={name=name,prefix=prefix,hashes=hashes,width_sp=width,instance_sha256=asset.instance_sha256,
    print_requirements=physical.print_requirements}
  F.mark('pattern_inline',{inline_ref=#inline,name=name,prefix=prefix,width=actual_width,height=actual_height})
  tex.sprint('\\includegraphics'..size..'{'..prefix..'.pdf}')
end
function M.queue(name,region,spread,protect,padding)
  need(started,'page patterns require the document body');init():asset(name)
  need(protect=='true' or protect=='false','protect-text must be true or false')
  F.mark('pattern_view',{name=name,options={region=region,spread=spread,protect_text=protect=='true',padding=padding*CM}})
end
function M.capture(box,label)
  if not core then return end
  local dimensions={};for name in ('paperwidth paperheight oddsidemargin evensidemargin hoffset voffset topmargin headheight headsep textwidth textheight footskip'):gmatch('%S+')do dimensions[name]=F.dimen(name)end
  local g=F.geometry(nil,'left');local headsep=dimensions.headsep*CM;local headheight=dimensions.headheight*CM
  local page={size={g.pw,g.ph},content={g.actual_left,g.ybot,g.actual_right,g.ytop},logical_number=F.page(),label=label,
    twoside=not not F.twoside,dimensions_sp=dimensions,header_top=g.ytop+headsep+headheight,markers=P.array(),inline_positions=P.array(),
    footer_bottom=g.footy-.5,running_regions={{g.actual_left,g.ytop+headsep,g.actual_right,g.ytop+headsep+headheight},
      {g.actual_left,g.footy-.5,g.actual_right,g.footy+.5}},reservations=P.array(),anchors=P.array()}
  local requests=P.array()
  for _,mark in ipairs(F.page_marks(box))do
    if mark.kind=='reserve_page'then page.reservations[#page.reservations+1]=P.plain(mark.arg)
    elseif mark.kind=='reserve_box'then
      local a=mark.arg;page.reservations[#page.reservations+1]={mark.x-a.pad,mark.y-a.d-a.pad,mark.x+a.w+a.pad,mark.y+a.h+a.pad}
    elseif mark.kind=='pattern_view'then requests[#requests+1]=P.plain(mark.arg)
    else
      page.anchors[#page.anchors+1]={id='mark/'..(#page.anchors+1),role=mark.kind,point={mark.x,mark.y},space='page'}
      page.markers[#page.markers+1]={kind=mark.kind,arg=mark.arg,x=mark.x,y=mark.y}
      if mark.kind=='pattern_inline'then
        local position=P.plain(mark.arg);position.x,position.y=mark.x,mark.y
        page.inline_positions[#page.inline_positions+1]=position
      end
    end
  end
  pending={page=page,requests=requests}
end
function M.background(index)
  if not core then return end
  need(pending,'shipout capture is missing');local item=pending;pending=nil;shipped=index
  local page=item.page;page.index=index;local results=P.array()
  for _,request in ipairs(item.requests)do
    local valid,result=pcall(core.place,core,request.name,page,request.options)
    need(valid,type(result)=='table' and result.message or tostring(result))
    local prefix,hashes=persist(result.key,{pdf=result.pdf,view=result.bytes.view,scene=result.bytes.scene,record=result.bytes.record})
    results[#results+1]={name=request.name,prefix=prefix,hashes=hashes,instance_sha256=result.asset.instance_sha256,
      record=result.record.id,view_ref=result.view.id,crop=P.plain(result.crop),transform=P.plain(result.view.transform),
      spread_document=result.spread_document and P.plain(result.spread_document) or nil}
    tex.sprint(string.format('\\put(%scm,%scm){\\makebox(0,0)[lb]{\\includegraphics{%s.pdf}}}',
      B.pdf_number(result.crop[1]-page.dimensions_sp.hoffset*CM),
      B.pdf_number(result.crop[2]-page.size[2]+page.dimensions_sp.voffset*CM),prefix))
  end
  pages[#pages+1]={geometry=P.plain(page),outputs=results}
end
function M.finish()
  if not core then return end
  core:finish()
  local current=source_bytes()
  for name,bytes in pairs(source)do need(current[name]==bytes,'source changed during this document build: '..name);current[name]=nil end
  need(next(current)==nil,'new source file appeared during this document build')
  local receipt={schema_version=1,adapter=require('pattern_tex').VERSION,runtime=core and 'LuaLaTeX',
    source_files=core.source_hashes,declarations=declarations,pages=pages,inline=inline,
    unique_generations=core.generations,physical_views=core.views,actual_shipped_pages=shipped,
    construction_policy='Recipe execution before shipout; cached validated instances and original planner-selected scenes at shipout'}
  local file=assert(io.open(tex.jobname..'-patterns.json','wb'));assert(file:write(P.serialize(receipt)));assert(file:close())
end
return M
