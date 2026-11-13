-- Meaningful editor invariant: styling/cropping never invoke structural generation.
local P,Q,R,H,V=require('pattern'),require('pattern_recipe'),require('pattern_registry'),require('pattern_hash'),require('pattern_render')
local fs=require('lfs');local source={}
for name in fs.dir('.')do if name:match('%.lua$')then local f=assert(io.open(name,'rb'));source[name]=f:read('*a');f:close()end end
local f=assert(io.open('examples/cli/periodic.recipe','rb'));local data=P.plain(Q.decode(f:read('*a')));f:close()
-- A separately named direct-view fixture, leaving the planned catalog unchanged.
data.id='editor/revision-fixture';data.view.extensions=nil;data.design.extensions=nil
local recipe=Q.new(data);local reg=R.new();local definition=require('pattern_periodic').register(reg)
local environment=Q.environment({revision='working/editor-revision',files={construction=source,style={},view={},renderer={}}},
 {lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/editor-revision'},{id=V.VERSION,version='1'})
local first=Q.execute(recipe,reg,environment);assert(first.record.status=='complete',P.serialize(first.record.diagnostics))
local original_bytes=first.bytes.instance;local original_svg=V.svg(V.plan(first.scene,first.instance,first.view,definition))
local generation_called=false;reg.generate=function()generation_called=true;error('editor revision invoked structural generator')end
local checks=0;local function check(ok,why)assert(ok,why);checks=checks+1 end
local function rejected(next_recipe,previous,instance,record,why)
 local ok,value=pcall(Q.revise,next_recipe,previous or recipe,instance or first.instance,record or first.record,reg,environment)
 check(not ok or value.record.status~='complete'and #value.record.outputs==0,why)
end
local changed=P.plain(recipe);changed.design.style.fill={.3,.6,.2};changed.view.crop[1]=.1
local revised=Q.revise(changed,recipe,first.instance,first.record,reg,environment)
check(revised.record.status=='complete','valid style/view revision rejected '..P.serialize(revised.record.diagnostics))
check(revised.bytes.instance==original_bytes,'style/view replaced instance bytes')
check(not generation_called,'style/view generated a replacement structure')
check(revised.record.lineage[1].role=='validated-style-view-revision'and revised.record.lineage[1].parent_ref==first.record.id,'revision lineage not bound')
check(revised.record.dependencies.cache.structure~=nil,'missing structural cache identity')
check(Q.structural_digest(recipe)==Q.structural_digest(changed),'style/view changed structural input identity')
check(V.svg(V.plan(revised.scene,revised.instance,revised.view,definition))~=original_svg,'style/crop did not affect actual vector export')
local plain_replay=Q.replay(changed,first.instance,first.record,reg,environment)
check(plain_replay.record.status=='failed','ordinary replay silently accepted a changed recipe')
local structural=P.plain(changed);structural.design.seed=structural.design.seed+1;rejected(structural,nil,nil,nil,'changed seed was treated as styling')
structural=P.plain(changed);structural.design.parameters.lattice_step=.9;rejected(structural,nil,nil,nil,'changed lattice was treated as styling')
structural=P.plain(changed);structural.design.document.bounds[1]=structural.design.document.bounds[1]-.1;rejected(structural,nil,nil,nil,'changed construction bounds were treated as styling')
local false_previous=P.plain(recipe);false_previous.design.style.marker=false
rejected(changed,false_previous,nil,nil,'wrong previous recipe accepted')
local corrupted=P.plain(first.record);corrupted.id='build/'..string.rep('0',64)
rejected(changed,nil,nil,corrupted,'altered record identity accepted')
corrupted=P.plain(first.record);corrupted.runtime.version='altered-host'
rejected(changed,nil,nil,corrupted,'altered record body accepted')
local corrupt_instance=P.plain(first.instance);corrupt_instance.structures.tiling.vertices[1].point[1]=corrupt_instance.structures.tiling.vertices[1].point[1]+.001
rejected(changed,nil,corrupt_instance,nil,'altered stored geometry accepted')
check(not generation_called,'failure path invoked structural generator')
local recovered=Q.revise(changed,recipe,first.instance,first.record,reg,environment)
check(recovered.record.status=='complete'and recovered.bytes.instance==original_bytes,'recoverable error lost stored work')
for _,name in ipairs{'build','build/editor-revision'}do fs.mkdir(name)end
local receipt={checks=checks,source_digest=environment.source.digest,actual_lua=_VERSION,generator_bypassed=true,
 original_instance_sha256=H.sha256(original_bytes),revised_instance_sha256=H.sha256(revised.bytes.instance),actual_svg_changed=true,
 parent_record=first.record.id,revision_record=revised.record.id,scope='Shared core revision contract; full editor/browser/CI acceptance remains stage32'}
local out=assert(io.open('build/editor-revision/receipt-'.._VERSION:gsub(' ','-')..'.json','wb'));out:write(P.serialize(receipt));out:close()
print('Checked editor style/view revision',checks,_VERSION)
return receipt
