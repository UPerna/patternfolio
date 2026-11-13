-- External XeLaTeX host. Semantic construction and view planning stay in pattern_tex.
local P,H,V,B=require('pattern'),require('pattern_hash'),require('pattern_render'),require('pattern_bytes')
local M={VERSION='pattern-xetex-records-v1'}
local CM=2.54/(72.27*65536)
local function need(ok,why)assert(ok,'florilegium patterns: '..why)end
function M.replace(path,bytes)
  local f=io.open(path,'rb');local old
  if f then old=f:read('*a');f:close();if old==bytes then return end end
  f=assert(io.open(path..'.tmp','wb'));assert(f:write(bytes));assert(f:close())
  local ok,reason=os.rename(path..'.tmp',path)
  if ok then return end
  -- Windows rename cannot replace an existing file. Retain the previous
  -- generated metadata under its content hash before publishing the new one.
  need(old~=nil,'cannot publish generated metadata: '..tostring(reason))
  local backup=path..'.previous-'..H.sha256(old)
  local saved=io.open(backup,'rb')
  if saved then
    local bytes_saved=saved:read('*a');saved:close();need(bytes_saved==old,'previous metadata backup has different bytes')
    assert(os.remove(path))
  else assert(os.rename(path,backup))end
  ok,reason=os.rename(path..'.tmp',path)
  if not ok then os.rename(backup,path);error('cannot publish generated metadata: '..tostring(reason),0)end
end
function M.records()
  local r={declarations={},inputs={},inline={},pages={},marks={},order=0}
  local env={
    PHEADER=function(t)need(not r.header,'duplicate external header');r.header=t end,
    PINPUT=function(t)r.order=r.order+1;t.order=r.order;r.inputs[#r.inputs+1]=t end,
    PDECLARE=function(t)r.order=r.order+1;t.order=r.order;r.declarations[#r.declarations+1]=t end,
    PINLINE=function(t)need(not r.inline[t.id],'duplicate inline id');r.inline[t.id]=t end,
    PPAGE=function(t)need(not r.pages[t.n],'duplicate physical page');r.pages[t.n]=t end,
    PMARK=function(t)local a=r.marks[t.n] or {};r.marks[t.n]=a;a[#a+1]=t end,
    PEND=function(t)need(not r.finish,'duplicate external finish');r.finish=t end,
  }
  return r,env
end
function M.render(base,r,root)
  local legacy=not r.header and not r.finish and #r.inputs==0 and #r.declarations==0 and #r.inline==0 and next(r.pages)==nil and next(r.marks)==nil
  need(legacy or r.header and r.header.schema_version==1 and r.header.adapter==require('pattern_tex').VERSION,
    'unsupported or missing external pattern record version')
  need(legacy or r.header.engine=='XeTeX' and r.finish,'incomplete external pattern records')
  if not legacy then
    need(type(r.finish.active)=='boolean' and type(r.finish.pending)=='boolean','external pass flags must be booleans')
    for key,maximum in pairs({shipped=10000,inline_count=100000})do
      local n=r.finish[key];need(type(n)=='number' and n>=0 and n<=maximum and n%1==0,'invalid external '..key..' count')
    end
    for id in pairs(r.inline)do need(type(id)=='number' and id%1==0 and id>=1 and id<=r.finish.inline_count,'inline id leaves declared record range')end
    for index in pairs(r.pages)do need(type(index)=='number' and index%1==0 and index>=1 and index<=r.finish.shipped,'physical page leaves declared record range')end
    for index in pairs(r.marks)do need(type(index)=='number' and index%1==0 and index>=1 and index<=r.finish.shipped,'mark has no actual shipped page')end
  end
  local lfs=require('lfs');local dependencies,outputs={},{}
  local function absolute(path)
    if path:match('^[/\\]') or path:match('^%a:[/\\]')then return path end
    return lfs.currentdir()..'/'..path
  end
  local function read(path,limit)
    local f=assert(io.open(path,'rb'),'florilegium patterns: input not found '..path)
    local bytes=f:read((limit or 2*1024*1024)+1);f:close()
    need(bytes and #bytes<=(limit or 2*1024*1024),'input exceeds byte limit: '..path)
    dependencies[absolute(path)]=H.sha256(bytes);return bytes
  end
  local function resolve(path)
    need(type(path)=='string' and #path>0 and not path:find('%z'),'invalid input filename')
    local f=io.open(path,'rb');if f then f:close();return path end
    local found=kpse.find_file(path);need(found,'input not found '..path);return found
  end
  local source={}
  for name in lfs.dir(root)do
    if name:match('%.lua$') or name:match('^florilegium.*%.sty$') or name:match('^florilegium.*%.def$')then
      source[name]=read(root..'/'..name,16*1024*1024)
    end
  end
  local source_hashes={};for name,bytes in pairs(source)do source_hashes[name]=H.sha256(bytes)end
  if legacy or not r.finish.active then
    need(#r.declarations==0 and #r.inputs==0 and #r.inline==0 and next(r.pages)==nil,'inactive external records contain patterns')
    return {dependencies=dependencies,outputs=outputs,source_files=source_hashes,active=false}
  end
  local runtime='XeTeX/'..tostring(r.header.version)..'/'..tostring(r.header.revision)..'/external/'.._VERSION
  local core=require('pattern_tex').new({source=source,runtime=runtime})
  local bindings,binding_order,declarations,inline,pages={},{},P.array(),P.array(),P.array()
  local function write_new(path,bytes)
    local f=io.open(path,'rb')
    if f then local old=f:read('*a');f:close();need(old==bytes,'existing generated filename has different bytes: '..path)
    else f=assert(io.open(path,'wb'));assert(f:write(bytes));assert(f:close())end
    outputs[path]=H.sha256(bytes)
  end
  local function persist(key,files)
    local prefix='florilegium-pattern-'..key;local hashes={}
    for suffix,bytes in pairs(files)do
      write_new(prefix..'.'..suffix,bytes);hashes[suffix]=H.sha256(bytes)
    end
    return prefix,hashes
  end
  for _,item in ipairs(r.inputs)do
    need(type(item.name)=='string' and #item.name>0 and not bindings[item.name],'duplicate or empty dependency name')
    bindings[item.name]=read(resolve(item.path))
    binding_order[item.name]=item.order
  end
  for _,item in ipairs(r.declarations)do
    local bytes=read(resolve(item.path));local q=require('pattern_recipe').decode(bytes);local inputs={}
    for _,group in pairs(q.dependencies)do for key in pairs(group)do
      inputs[key]=assert(bindings[key],'florilegium patterns: bind dependency '..key..' before declaring this recipe')
      need(binding_order[key]<item.order,'bind dependency '..key..' before declaring this recipe')
    end end
    local asset=core:declare(item.name,bytes,inputs)
    local files={recipe=asset.recipe_bytes,record=P.serialize(asset.result.record),view=P.serialize(asset.result.view),scene=asset.result.bytes.scene}
    if asset.result.instance.extensions.legacy then
      local manifest,blocks=require('pattern_botanical_legacy').encode_bundle(asset.result.instance);files.instance=manifest
      for hash,data in pairs(blocks)do files['block-'..hash..'.json']=data end
    else files.instance=asset.result.bytes.instance end
    local prefix,hashes=persist(asset.key,files)
    declarations[#declarations+1]={name=item.name,family=asset.definition.id,prefix=prefix,hashes=hashes,
      instance_sha256=asset.instance_sha256,generation_record=asset.result.record.id}
  end
  local metadata={}
  local function macro(name,value)
    metadata[#metadata+1]='\\expandafter\\gdef\\csname '..name..'\\endcsname{'..value..'}\n'
  end
  for id=1,r.finish.inline_count do
    local item=r.inline[id];need(item and item.id==id,'inline ids are not contiguous')
    local plan,asset,physical=core:inline(item.name,item.width*CM)
    local pdf=V.pdf(plan);local key=H.value('tex/inline',{source=asset.environment.source.digest,pdf=H.sha256(pdf)})
    local prefix,hashes=persist(key,{pdf=pdf})
    inline[id]={name=item.name,prefix=prefix,hashes=hashes,width_sp=item.width,instance_sha256=asset.instance_sha256,
      width=physical.width,height=physical.height,print_requirements=physical.print_requirements}
    macro('flo@pinline@'..id,prefix)
  end
  local F=require('florilegium');local original={dimen=F.dimen,page=F.page,twoside=F.twoside}
  for index=1,r.finish.shipped do
    local d=r.pages[index];need(d and d.n==index,'missing actual shipped-page record')
    F.dimen=function(name)return assert(d[name],'missing page dimension '..name)end
    F.page=function()return d.page end;F.twoside=d.twoside
    local g=F.geometry(nil,'left');local dimensions={}
    for name in ('paperwidth paperheight oddsidemargin evensidemargin hoffset voffset topmargin headheight headsep textwidth textheight footskip'):gmatch('%S+')do dimensions[name]=d[name]end
    local page={index=index,size={g.pw,g.ph},content={g.actual_left,g.ybot,g.actual_right,g.ytop},
      logical_number=d.page,label=d.label,twoside=d.twoside,dimensions_sp=dimensions,
      header_top=g.ytop+(d.headsep+d.headheight)*CM,footer_bottom=g.footy-.5,
      running_regions={{g.actual_left,g.ytop+d.headsep*CM,g.actual_right,g.ytop+(d.headsep+d.headheight)*CM},
        {g.actual_left,g.footy-.5,g.actual_right,g.footy+.5}},
      markers=P.array(),inline_positions=P.array(),reservations=P.array(),anchors=P.array()}
    local requests={}
    for _,mark in ipairs(r.marks[index] or {})do
      local x,y=mark.x*CM,mark.y*CM;local a=mark.arg
      if mark.kind=='reserve_page'then
        page.reservations[#page.reservations+1]={(a.x-a.pad)*CM,(a.y-a.pad)*CM,(a.x+a.w+a.pad)*CM,(a.y+a.h+a.pad)*CM}
      elseif mark.kind=='reserve_box'then
        page.reservations[#page.reservations+1]={x-a.pad*CM,y-(a.d+a.pad)*CM,x+(a.w+a.pad)*CM,y+(a.h+a.pad)*CM}
      elseif mark.kind=='pattern_view'then
        need(a.protect=='true' or a.protect=='false','protect-text must be true or false')
        requests[#requests+1]={name=a.name,options={region=a.region,spread=a.spread,protect_text=a.protect=='true',padding=a.padding*CM}}
      else
        local argument=a
        if mark.kind=='pattern_inline'then
          local asset=inline[a.id];need(asset and asset.name==a.name,'inline position refers to a different asset')
          argument={inline_ref=a.id,name=asset.name,prefix=asset.prefix,width=asset.width,height=asset.height}
          local position=P.plain(argument);position.x,position.y=x,y;page.inline_positions[#page.inline_positions+1]=position
        end
        page.anchors[#page.anchors+1]={id='mark/'..(#page.anchors+1),role=mark.kind,point={x,y},space='page'}
        page.markers[#page.markers+1]={kind=mark.kind,arg=P.plain(argument),x=x,y=y}
      end
    end
    local results=P.array();local commands={}
    for _,request in ipairs(requests)do
      local valid,result=pcall(core.place,core,request.name,page,request.options)
      need(valid,type(result)=='table' and result.message or tostring(result))
      local prefix,hashes=persist(result.key,{pdf=result.pdf,view=result.bytes.view,scene=result.bytes.scene,record=result.bytes.record})
      results[#results+1]={name=request.name,prefix=prefix,hashes=hashes,instance_sha256=result.asset.instance_sha256,
        record=result.record.id,view_ref=result.view.id,crop=P.plain(result.crop),transform=P.plain(result.view.transform),
        spread_document=result.spread_document and P.plain(result.spread_document) or nil}
      commands[#commands+1]=string.format('\\put(%scm,%scm){\\makebox(0,0)[lb]{\\includegraphics{%s.pdf}}}',
        B.pdf_number(result.crop[1]-d.hoffset*CM),B.pdf_number(result.crop[2]-page.size[2]+d.voffset*CM),prefix)
    end
    macro('flo@ppage@'..index,table.concat(commands));pages[#pages+1]={geometry=page,outputs=results}
  end
  F.dimen,F.page,F.twoside=original.dimen,original.page,original.twoside
  core:finish()
  local trace={schema_version=1,adapter=require('pattern_tex').VERSION,runtime=runtime,protocol=M.VERSION,
    source_files=core.source_hashes,declarations=declarations,pages=pages,inline=inline,
    unique_generations=core.generations,physical_views=core.views,actual_shipped_pages=r.finish.shipped,
    input_pass_pending=r.finish.pending,
    construction_policy='Same semantic core and shared renderer; external construction between no-shell-escape TeX passes'}
  local function replace(path,bytes)
    M.replace(path,bytes);outputs[path]=H.sha256(bytes)
  end
  replace(base..'-patterns.json',P.serialize(trace));replace(base..'-patterns.tex',table.concat(metadata))
  for path,digest in pairs(dependencies)do
    local f=assert(io.open(path,'rb'));local now=f:read('*a');f:close();need(H.sha256(now)==digest,'source or recipe changed while rendering: '..path)
  end
  return {dependencies=dependencies,outputs=outputs,source_files=source_hashes,active=true,protocol=M.VERSION,
    input_pass_pending=r.finish.pending}
end
return M
