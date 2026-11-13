-- Actual stage08 botanical construction and compatibility evidence.
package.path="./?.lua;"..package.path
local P,R,D,L,Q=require("pattern"),require("pattern_registry"),require("pattern_document"),require("pattern_planner"),require("pattern_recipe")
local A,H,Render=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local Legacy,Panel=require("pattern_botanical_legacy"),require("pattern_botanical_panel")
local files={"tools/botanicalcheck.lua","tools/botanical_oracle.py"};local fs=require("lfs")
for name in fs.dir(".")do if name:match("%.lua$")then files[#files+1]=name end end
table.sort(files,P.byte_less)
local function read(path)local f=assert(io.open(path,"rb"));local data=f:read("*a");f:close();return data end
local source,inputs={},{}
for _,name in ipairs(files)do inputs[name]=read(name);source[#source+1]={path=name,sha256=H.sha256(inputs[name]:gsub("\r\n","\n"))}end
local digest=H.sha256(P.serialize(source));local root="build/botanical/"..digest
for _,path in ipairs({"build","build/botanical",root})do fs.mkdir(path)end
local outputs={}
local function write(name,bytes)outputs[name]=A.write(root.."/"..name,bytes)end
local checks=0
local function check(ok,message)assert(ok,message);checks=checks+1 end
local registry=R.new();local d=Panel.register(registry)
local doc=D.new({id="panel-document",unit="cm",frame={id="panel/world",origin={0,0}},twoside=false,spreads=P.array(),pages={{id="panel",number=1,size={12,11},origin={0,0},trim={0,0,12,11},bleed={0,0,0,0},margins={0,0,0,0},binding_offset=0,offset={0,0},protected_regions={{id="callout",role="protected_content",space="page",bounds={6,4,7,5.2}}},anchors={{id="root",role="root",space="page",point={3,1.8}}}}}})
local profile=L.profile(d,{mode="adaptive",generation_region="media",construction_scale=16,density_parameter="density"})
local spec=P.specification({id="asymmetric-panel",definition_ref={id=d.id,version=d.version},seed=7,parameters={density=0.6},inputs={},style={},constraints={region={unit="cm",points={{1,1},{9,1},{11,5},{8,10},{2,9}}}},document={unit="cm",bounds={0,0,12,11},protected_regions=P.array()},budget={objects=10000,operations=2000000,bytes=64*1024*1024}},d)
local recipe=assert(L.recipe(d,spec,doc,"panel",profile,{},{region="media"}))
local runtime=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")
local env=Q.environment({revision="working/botanical/"..digest,files={construction=inputs,style={},view={},renderer={}}},{lua=_VERSION,host=runtime},{id=Render.VERSION,version="1"})
local saved=Q.encode(recipe);local out=Q.execute(Q.decode(saved),registry,env)
check(out.record.status=="complete",P.serialize(out.record))
local x=out.instance;check(x.extensions.panel.accepted==7 and #x.extensions.panel.attempts==8,"panel no longer exercises successful and rejected rules")
local corrupt=P.plain(x);corrupt.extensions.panel.resources[1].bounds[1]=corrupt.extensions.panel.resources[1].bounds[1]+0.001
check(not pcall(Panel.validate,corrupt,d),"forged paint envelope accepted")
local bad=P.plain(spec);bad.constraints.region.points[3]={3,4}
local rejected=Q.execute(assert(L.recipe(d,bad,doc,"panel",profile,{},{})),registry,env)
check(rejected.record.status=="failed"and #rejected.record.outputs==0,"nonconvex input accepted")
local limited=Q.execute(recipe,registry,env,{limits={objects=0,operations=20,bytes=100}})
check(limited.record.status=="failed"and #limited.record.outputs==0,"bounded search published an unfinished result")
local cancelled=Q.execute(recipe,registry,env,{cancelled=function()return true end})
check(cancelled.record.status=="cancelled"and #cancelled.record.outputs==0,"cancelled recipe published output")
local crop=assert(L.recipe(d,spec,doc,"panel",profile,{},{crop={0.4,0.4,11.6,10.6}}))
check(Q.cache_keys(crop,env).structure==out.keys.structure and Q.cache_keys(crop,env).view~=out.keys.view,"panel crop changed construction key")
local plan=Render.plan(out.scene,x,out.view,d)
write("panel.pdf",Render.pdf(plan));write("panel.svg",Render.svg(plan));write("panel.instance",out.bytes.instance);write("panel.scene",out.bytes.scene);write("panel.recipe",saved)
local unmasked=P.plain(out.view);unmasked.id=unmasked.id.."/unmasked";unmasked.protected_regions=P.array()
local v=P.view(unmasked,x,d);local ctx=R.context({seed=7,source={revision=digest},limits={objects=10000,operations=2000000,bytes=64*1024*1024}})
local scene=registry:lower(d.id,x,v,{},ctx);write("panel-unmasked.pdf",Render.pdf(Render.plan(scene,x,v,d)))
local legacy={}
local peak={};local defs=require("grow").motifs;local names={};for name in pairs(defs)do names[#names+1]=name end;table.sort(names,P.byte_less)
local function measure(name,size,draw)
  local ink=require("ink");local paths=ink.capture(function()draw(ink.rng(7),size)end)
  local Bounds=require("pattern_bounds");local policy=require("pattern_geometry").policy("cm",64);local bounds={}
  for _,p in ipairs(paths)do if p.op=="path"then bounds[#bounds+1]=Bounds.path(p.commands,p.paint,p.transform,policy)end end
  local box=Bounds.union(bounds,"cm");assert(not box.empty,"maximum motif has no paint: "..name)
  peak[#peak+1]={name=name,size=size,seed=7,bounds=P.plain(box.bounds),paint_paths=#bounds}
end
for _,name in ipairs(names)do measure(name,defs[name].smax,defs[name].draw)end
local flora=require("flora")
measure("maximum-custom-focal",1.75*1.5,flora.flower)
measure("grown-snail",0.9,flora.snail)
for _,facing in ipairs({-1,1})do measure("grown-bird/"..facing,2.7,function(r,s)flora.bird(r,s,{facing=facing})end)end
check(#peak==18,"maximum motif/visitor probes missing")
for _,mode in ipairs({"grown","authored"})do
  local g={pw=21,ph=29.7,textleft=6.8,textright=18.8,ytop=25.4,ybot=3,colright=6.4,headrule=26.1,footy=1.9,seed=7,spill=0,spilly=19,visitors=false,layout={style="quiet",header=false}}
  local ink=require("ink");local palette=ink.palette_snapshot()
  local engine=require(mode=="grown"and"grow"or"authored")
  local plain=ink.capture(function()engine.page(g)end)
  local instance,definition,valid=Legacy.capture(mode,g,palette)
  check(valid.ok and valid.attachments>0,"missing actual sampled stem attachments")
  local raw=Legacy.operations(instance);local painted={}
  for i,op in ipairs(raw)do
    if op.op=="path"then painted[#painted+1]=op end
    local item=P.plain(op);item.semantic_ref=nil
    assert(P.serialize(item)==P.serialize(plain[i]),"observation changed legacy watercolor bytes")
  end
  check(#raw==#plain,"observation changed operation count")
  local manifest,blocks=Legacy.encode_bundle(instance)
  local imported=Legacy.decode_bundle(manifest,function(sha)return blocks[sha]end,definition)
  check(P.serialize(imported)==P.serialize(instance),"bundle did not replay exact semantic and paint data")
  check(not pcall(Legacy.decode_bundle,manifest,function(sha)return blocks[sha].." "end,definition),"modified capture bytes accepted")
  local vv=P.view({id="legacy/"..mode,instance_ref=instance.id,unit="cm",transform={1,0,0,1,0,0},crop={0,0,21,29.7},protected_regions=P.array(),derived=false,validity="construction_preserved"},instance,definition)
  local ss=Legacy.lower(instance,vv,definition);local pp=Render.plan(ss,instance,vv,definition);local n=0
  for op in Render.operations(pp)do if op.op=="path"then
    n=n+1;local source_op=painted[n];assert(source_op and op.semantic_ref==source_op.semantic_ref and P.serialize(op.commands)==P.serialize(source_op.commands) and P.serialize(op.paint)==P.serialize(source_op.paint),"segmented renderer changed actual source paint")
  end end
  check(n==#painted,"segmented renderer lost source paths")
  write(mode..".pdf",Render.pdf(pp));write(mode..".svg",Render.svg(pp));write(mode..".manifest",manifest)
  legacy[mode]={nodes=#instance.structures.growth.nodes,attachments=valid.attachments,source_operations=#raw,paths=n,render_blocks=#pp.operation_segments}
end
local observer_count
if arg and arg[1]=="--legacy-layout"then
  observer_count=0
  local undo=Legacy.install(function(_,_,v)assert(v.ok);observer_count=observer_count+1 end)
  local ok,err=pcall(dofile,"tools/layoutcheck.lua");undo();assert(ok,err)
  check(observer_count==12,"wrapped legacy layoutcheck did not observe all12 existing pages")
end
local receipt={stage="08",source_digest=digest,source=source,checks=checks,runtime=_VERSION,host=runtime,outputs=outputs,legacy=legacy,maximum_size_bounds=peak,panel=P.plain(out.record),wrapped_layout_pages=observer_count}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..(observer_count and "-wrapped"or "")..".json",P.serialize(receipt).."\n")
print("botanicalcheck: "..checks.." contract checks; authored/grown observed paths and asymmetric panel; "..root)
