-- Incremental observation of the actual authored/grown algorithms. No altered
-- random draws, placement rules or inferred universal attachment guarantees.
local P,H=require("pattern"),require("pattern_hash")
local M={VERSION="legacy-botanical-capture-v1"}
local active=false
local validate_recording
local engines={}
local function engine(mode)
  if not engines[mode]then engines[mode]=require(mode=="grown"and"grow"or"authored").page end
  return engines[mode]
end
local names={"flower","lily","blossom","floret","bud","bell","leaf","leaflet","stem","cyme","sprig","umbel","seedhead","tendril","sparkle","rosette","hedera","butterfly","bee","snail","bird","divider","petal"}
local function copy_point(ink,p)local x,y=ink.to_page(p[1],p[2]);return{x,y}end
local function closest(p,stems)
  local best
  for _,stem in ipairs(stems)do for i=2,#stem.points do
    local a,b=stem.points[i-1],stem.points[i];local dx,dy=b[1]-a[1],b[2]-a[2];local q=dx*dx+dy*dy
    local u=q>0 and math.max(0,math.min(1,((p[1]-a[1])*dx+(p[2]-a[2])*dy)/q))or 0
    local x,y=a[1]+u*dx,a[2]+u*dy;local distance=math.sqrt((p[1]-x)^2+(p[2]-y)^2)
    if distance<=1e-9 and(not best or distance<best.distance)then best={parent=stem.id,segment=i-1,parameter=u,point={x,y},distance=distance,tolerance_cm=1e-9}end
  end end
  return best
end
function M.definition(mode)
  assert(mode=="authored"or mode=="grown","unknown botanical composition")
  return P.definition({id="botanical/legacy-"..mode,version="1",family="existing-"..mode.."-botanical",units="cm",capabilities={"growth"},parameters={},
    transforms={metric_constrained=false,reflection=true,uniform_scale=true},assumptions={"Actual existing composition; preserved quantized watercolor recording","Nested procedure dependencies are distinct from measured stem attachments","Unattached decorations and failed legacy routes are not certified connected"}})
end
-- g is the actual canonical host geometry/settings packet. The document adapter
-- owns physical origin/parity conversion; never silently derive a second origin.
function M.capture(mode,g,style,context,metadata_only)
  assert(not active,"botanical capture cannot reenter");assert(not g.anim,"legacy animation uses its original recording API; request its final static state here")
  local d=M.definition(mode);g=P.plain(g);style=P.plain(style or {})
  for key in pairs(style)do assert(key=="ink"or key=="accent"or key=="lift"or key=="color_mode","unsupported legacy paint option "..key)end
  local function color(c)
    assert(type(c)=="table"and #c==3,"RGB triple required")
    for _,n in ipairs(c)do assert(type(n)=="number"and n>=0 and n<=1,"invalid RGB component")end
    return c
  end
  local ink,flora=require("ink"),require("flora");local draw=engine(mode)
  local nodes={{id="composition",point={0,0},motif="composition",relationship="composition-group"}}
  local stems,stack,counts,originals={},{"composition"},{},{}
  local function current()return stack[#stack]end
  local function observe(name,fn)
    return function(...)
      if context then context:consume("objects",1);context:consume("operations",1)end
      counts[name]=(counts[name]or 0)+1;local id="primitive/"..name.."/"..counts[name];local point=copy_point(ink,{0,0})
      local args={...};local points
      if name=="stem"and type(args[1])=="table"then
        points={};for _,p in ipairs(args[1])do points[#points+1]=copy_point(ink,p)end
        assert(#points>=2,"legacy stem must have sampled geometry");point=points[1]
      end
      local attachment=closest(point,stems);local parent=current()
      local n={id=id,point=point,parent=attachment and attachment.parent or parent,motif=name,procedure_parent=parent,
        relationship=attachment and"measured-stem-attachment"or(parent=="composition"and"composition-member"or"nested-procedure")}
      if attachment then n.attachment=attachment end
      if points then n.sampled_points=points end
      nodes[#nodes+1]=n;stack[#stack+1]=id
      local result=table.pack(pcall(fn,...));stack[#stack]=nil
      if not result[1]then error(result[2],0)end
      if points then stems[#stems+1]={id=id,points=points}end
      return table.unpack(result,2,result.n)
    end
  end
  active=true
  for _,name in ipairs(names)do if type(flora[name])=="function"then originals[name]=flora[name];flora[name]=observe(name,flora[name])end end
  local stats
  local ok,operations,receipt=pcall(ink.capture,function()
    local rgb=color(style.ink or{0x24/255,0x56/255,0xC4/255});ink.set_ink(table.unpack(rgb))
    rgb=color(style.accent or{0xB4/255,0x66/255,0x2F/255});ink.set_accent(table.unpack(rgb))
    assert(style.lift==nil or type(style.lift)=="number"and style.lift>=0 and style.lift<=1,"invalid lift")
    ink.set_lift(style.lift or 0);ink.set_color_mode(style.color_mode or "color")
    stats=draw(g)
  end,{semantic_ref=current})
  for name,fn in pairs(originals)do flora[name]=fn end;active=false
  if not ok then error(operations,0)end
  local painted={};for _,op in ipairs(operations)do if op.op=="path"then painted[op.semantic_ref]=(painted[op.semantic_ref]or 0)+1 end end
  for _,n in ipairs(nodes)do n.surviving_paint_paths=painted[n.id]or 0;n.observation_scope="actual invoked procedure; zero surviving paths may reflect LOD or reservation rejection"end
  -- Keep the existing per-record object guard. Large watercolor recordings are
  -- stored as independently bounded/hash-verified JSON blocks, not one enormous
  -- nested object graph in the semantic instance.
  assert(#operations<=100000,"legacy recording exceeds100000 drawing operations")
  local chunks=not metadata_only and {} or nil
  if chunks then for first=1,#operations,32 do
    local part={};for i=first,math.min(first+31,#operations)do part[#part+1]=operations[i]end
    local bytes=P.serialize(part);assert(#bytes<=2*1024*1024,"one legacy recording block exceeds bounded JSON profile")
    chunks[#chunks+1]={content=bytes,sha256=H.sha256(bytes),count=#part}
  end end
  local x=P.instance({id=d.id.."/instance/"..H.value("botanical/legacy-input",{geometry=g,style=style}),definition_ref={id=d.id,version=d.version},
    frame=context and P.plain(context.frame)or{id="botanical/world",unit="cm",dimension=2,handedness="right",origin={0,0}},
    structures={growth={nodes=nodes,roots={"composition"}}},provenance={generator=d.id,generator_version=d.version,seed=g.seed,construction=M.VERSION},
    extensions={legacy={geometry=g,style=style,stats=stats or{},primitive_counts=counts,chunks=chunks,capture=receipt,
      recording_scope=metadata_only and "native host observation; paint emitted by the original sink" or "complete neutral recording",
      attachment_scope="existing sampled stem segments within1e-9cm; otherwise dependency grouping only",paint_scope="frozen original watercolor recording; no arbitrary repaint inference"}}},d)
  return x,d,validate_recording(x,operations)
end
function M.operations(instance)
  local legacy=instance.extensions.legacy;local operations={}
  assert(legacy.chunks,"native observation has no paint blocks; request complete capture to replay vector paint")
  assert(#legacy.chunks<=3125,"legacy block count exceeds recording profile")
  for _,block in ipairs(legacy.chunks)do
    assert(H.sha256(block.content)==block.sha256,"legacy recording block digest mismatch")
    local part=require("pattern_parse").decode(block.content);assert(#part==block.count and #part<=32,"legacy recording block count mismatch")
    for _,op in ipairs(part)do operations[#operations+1]=op end
  end
  assert(#operations==legacy.capture.count,"legacy recording total count mismatch")
  return operations
end
function M.encode_bundle(instance)
  local data=P.plain(instance);local blocks={}
  for _,block in ipairs(assert(data.extensions.legacy.chunks,"bundle requires complete neutral capture"))do
    assert(H.sha256(block.content)==block.sha256,"legacy recording block digest mismatch")
    blocks[block.sha256]=block.content;block.bytes=#block.content;block.content=nil
  end
  local manifest=P.serialize(data);assert(#manifest<=2*1024*1024,"legacy semantic manifest exceeds bounded JSON profile")
  return manifest,blocks
end
function M.decode_bundle(manifest,provider,definition)
  assert(type(provider)=="function","verified legacy recording block provider required")
  local data=require("pattern_parse").decode(manifest)
  local chunks=data.extensions.legacy.chunks;assert(#chunks<=3125,"legacy block count exceeds profile")
  for _,block in ipairs(chunks)do
    assert(block.content==nil and H.is_digest(block.sha256)and block.bytes>0 and block.bytes<=2*1024*1024,"invalid legacy bundle block reference")
    local bytes=provider(block.sha256);assert(type(bytes)=="string"and #bytes==block.bytes and H.sha256(bytes)==block.sha256,"missing or modified legacy bundle block")
    block.content=bytes;block.bytes=nil
  end
  local instance=P.instance(data,definition);M.validate(instance,definition);return instance
end
function M.lower(instance,view,definition)
  local x=P.instance(P.plain(instance),definition);local v=P.view(P.plain(view),x,definition)
  local raw=M.operations(x);local m=P.plain(v.transform)
  local ops,resources,clips,paths,boxes=P.array(),P.array(),{},{},{};local owner
  local Bounds,policy=require("pattern_bounds"),require("pattern_geometry").policy("cm",64)
  local function flush()
    if #paths==0 then return end
    local asset_ops={};for _,clip in ipairs(clips)do asset_ops[#asset_ops+1]=clip end
    for _,p in ipairs(paths)do asset_ops[#asset_ops+1]=p end
    for _=1,#clips do asset_ops[#asset_ops+1]={op="pop_clip"}end
    local bounds=Bounds.union(boxes,"cm");local id="legacy-paint/"..(#resources+1)
    local content=P.serialize({kind="vector_asset",schema_version=1,unit="cm",operations=asset_ops})
    assert(#content<=2*1024*1024,"legacy paint asset block exceeds bounded JSON profile")
    resources[#resources+1]={id=id,kind="symbol",unit="cm",bounds=P.plain(bounds.bounds),variants={scene={encoding="utf8",content=content,sha256=H.sha256(content)}}}
    ops[#ops+1]={op="symbol",semantic_ref=owner,resource_ref=id,transform=m}
    paths,boxes={},{}
  end
  for _,op in ipairs(raw)do
    if op.op=="push_clip"then flush();clips[#clips+1]=op
    elseif op.op=="pop_clip"then flush();assert(table.remove(clips),"legacy recording clip underflow")
    elseif op.op=="path"then
      if owner~=op.semantic_ref or #paths==24 then flush();owner=op.semantic_ref end
      paths[#paths+1]=op;boxes[#boxes+1]=Bounds.path(op.commands,op.paint,op.transform,policy)
    else error("unsupported legacy recording operation")end
  end
  flush();assert(#clips==0,"legacy recording clip imbalance")
  return P.scene({id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=resources,extensions={render_profile="segmented-ops-v1"}},x,v,definition)
end
validate_recording=function(x,operations)
  local nodes,painted={},{}
  for _,n in ipairs(x.structures.growth.nodes)do nodes[n.id]=n end
  for _,op in ipairs(operations)do if op.op=="path"then
    assert(nodes[op.semantic_ref],"legacy paint references an absent primitive");painted[op.semantic_ref]=(painted[op.semantic_ref]or 0)+1
  end end
  local attachments=0
  for _,n in ipairs(x.structures.growth.nodes)do
    assert(n.surviving_paint_paths==(painted[n.id]or 0),"surviving paint count mismatch")
    if n.attachment then
      local a=n.attachment;local parent=assert(nodes[a.parent],"missing attached stem")
      assert(n.parent==parent.id and parent.sampled_points,"attachment parent is not its recorded stem")
      assert(a.tolerance_cm==1e-9 and a.parameter>=0 and a.parameter<=1,"invalid attachment tolerance/parameter")
      local p,q=parent.sampled_points[a.segment],parent.sampled_points[a.segment+1];assert(p and q,"invalid attachment segment")
      local dx,dy=p[1]+a.parameter*(q[1]-p[1])-n.point[1],p[2]+a.parameter*(q[2]-p[2])-n.point[2]
      assert(math.sqrt(dx*dx+dy*dy)<=1e-9,"attachment is geometrically disconnected")
      attachments=attachments+1
    end
  end
  return {ok=true,attachments=attachments,checks={"actual primitive IDs and surviving paint references","sampled stem attachment segment/parameter residual <=1e-9cm","composition dependencies distinguished from verified physical attachment"}}
end
function M.validate(instance,definition)
  local x=P.instance(P.plain(instance),definition)
  return validate_recording(x,M.operations(x))
end
function M.register(registry,mode)
  local d=M.definition(mode)
  registry:register(d,{
    generate=function(s,c)
      assert(s.extensions and s.extensions.legacy_geometry,"actual legacy host geometry required")
      local g=P.plain(s.extensions.legacy_geometry);assert(g.seed==s.seed,"host/specification seed mismatch")
      return M.capture(mode,g,s.extensions.legacy_capture_style,c)
    end,
    validate=function(x)return M.validate(x,d)end,
    lower=function(x,v,style)
      assert(next(style)==nil,"legacy adapter replays its frozen paint; create a new explicit recipe for paint changes")
      return M.lower(x,v,d)
    end,
  })
  return d
end
-- Opt-in drop-in host entrypoint: returns the original stats first and the
-- validated common instance second. Original drawing bytes still go through
-- the host's existing sink; header, initial and inline APIs remain native.
function M.entrypoint(mode,observed)
  M.definition(mode);local draw=engine(mode)
  assert(observed==nil or type(observed)=="function","instance observer callback required")
  return function(g)
    if g.anim then return draw(g)end -- unchanged original recording and endpoint API
    local x,d,validation=M.capture(mode,g,require("ink").palette_snapshot(),nil,true)
    if observed then observed(x,d,validation)end
    local stats=draw(g)
    return stats,x,d
  end
end
function M.install(observed)
  local installed={}
  for _,mode in ipairs({"authored","grown"})do
    local module=require(mode=="grown"and"grow"or"authored")
    local original=module.page;local wrapper=M.entrypoint(mode,observed)
    module.page=wrapper;installed[#installed+1]={module=module,original=original,wrapper=wrapper}
  end
  return function()
    for _,item in ipairs(installed)do assert(item.module.page==item.wrapper,"composition entrypoint changed since installation")end
    for _,item in ipairs(installed)do item.module.page=item.original end
  end
end
return M
