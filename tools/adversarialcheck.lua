-- Stage33: deliberately corrupt real generated instances; query/crop/style order.
local P,Q,C,R,H,V=require('pattern'),require('pattern_recipe'),require('pattern_cli_core'),require('pattern_registry'),require('pattern_hash'),require('pattern_render')
local fs=require('lfs');local Parse=require('pattern_parse');local source={}
local function read(name)local f=assert(io.open(name,'rb'));local b=f:read('*a');f:close();return b end
for name in fs.dir('.')do if name:match('%.lua$')then source[name]=read(name)end end
source['tools/adversarialcheck.lua']=read('tools/adversarialcheck.lua')
local env=Q.environment({revision='working/adversarial33',files={construction=source,style={},view={},renderer={}}},{lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/adversarial33'},{id=V.VERSION,version='1'})
local results=P.array();local failures=P.array();local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1 end
local root='build/adversarial'..(PATTERN_TEST_VARIANT or '');fs.mkdir('build');fs.mkdir(root)
local function save(name,value)local f=assert(io.open(root..'/'..name,'wb'));f:write(P.serialize(value));f:close()end
local mutations={
 periodic={{'duplicate-cell',function(x)local t=x.structures.tiling;t.cells[#t.cells+1]=P.plain(t.cells[1])end}},
 penrose={{'matching-class',function(x)x.structures.tiling.edges[1].matching.class='invented'end}},
 spectre={{'illicit-reflection',function(x)x.structures.tiling.cells[1].exact_transform.reflected=true end},{'corrupt-hierarchy',function(x)x.structures.tiling.hierarchy[1].type='Invented'end}},
 micrography={{'near-integer-line',function(x)x.extensions.micrography.positions[1].line=1-2^-53 end},{'near-integer-span',function(x)x.extensions.micrography.positions[1].spans[1][1]=1-2^-53 end},{'triangle-reference',function(x)x.extensions.micrography.field.triangles[1][1]=999999 end},{'boundary-label',function(x)local s=x.extensions.micrography.field.labels.samples[1];s.label=1-s.label end}},
}
local selected=arg and arg[1]and {arg[1]}or {'periodic','penrose','spectre','micrography'}
for _,name in ipairs(selected)do
 local q=Q.decode(read('examples/cli/'..name..'.recipe'));local reg,d=C.registry(q.definition.id)
 local first=Q.execute(q,reg,env);check(first.record.status=='complete',name..': '..P.serialize(first.record.diagnostics))
 save(name..'-instance.json',first.instance);save(name..'-recipe.json',q)
 local observed=P.array()
 for _,probe in ipairs(mutations[name])do
  local bad=P.plain(first.instance);probe[2](bad)
  local context=R.context({seed=q.design.seed,source=env.source,limits=q.design.budget,frame=first.instance.frame})
  local ok,err=pcall(reg.validate,reg,d.id,bad,context)
  observed[#observed+1]={name=probe[1],detected=not ok,diagnostic=not ok and tostring(err)or 'CORRUPTION ACCEPTED'}
  save(name..'-'..probe[1]..'-corruption.json',{seed=q.design.seed,family=d.id,generator_version=d.version,instance=bad,expected='rejected structural corruption',actual=observed[#observed]})
  if ok then failures[#failures+1]=name..'/'..probe[1]end
 end
 local calls=0;reg.generate=function()calls=calls+1;error('view/style invoked generator')end
 local b=P.plain(q.view.crop);local w,h=b[3]-b[1],b[4]-b[2]
 local crops={{b[1],b[2],b[1]+.6*w,b[4]},{b[1]+.4*w,b[2],b[3],b[4]},b}
 local passes=P.array()
 for _,i in ipairs{2,1,3,1}do
  local edit=require('pattern_editor').apply(q,{schema_version=1,crop=crops[i],style={output_profile={schema_version=1,mode='monochrome'}}})
  local value=Q.revise(edit,q,first.instance,first.record,reg,env)
  if (name=='periodic'or name=='micrography')and i~=3 and value.record.status=='failed'then
   local message=name=='periodic'and 'no cells satisfy'or 'micrography-crop-would-hide-text'
   check(P.serialize(value.record.diagnostics):find(message,1,true)~=nil and #value.record.outputs==0,'Family-aware crop failure lost diagnostics or emitted accepted output')
   passes[#passes+1]={crop=i,status='rejected-by-declared-family-policy',diagnostic_sha256=H.value('diagnostic',value.record.diagnostics)}
  else
   check(value.record.status=='complete',name..' revision '..P.serialize(value.record.diagnostics));check(value.bytes.instance==first.bytes.instance,name..' view/style altered construction')
   passes[#passes+1]={crop=i,status='complete',instance_sha256=H.sha256(value.bytes.instance),scene_sha256=H.sha256(value.bytes.scene)}
  end
 end
 check(calls==0,'Generator called by view-only operation');check(P.serialize(passes[2])==P.serialize(passes[4]),'Query order changed repeated crop')
 results[#results+1]={family=name,seed=q.design.seed,corruptions=observed,crop_order=passes,generator_calls=calls,original_instance_sha256=H.sha256(first.bytes.instance)}
 print('Adversarial real family',name,#observed,'corruptions')
end
local receipt={status=#failures==0 and 'passed'or 'failed',source_digest=env.source.digest,actual_lua=_VERSION,checks=checks,results=results,escaped_corruptions=failures,scope='Single-agent controlled falsification, not independent reviewer; separate Python analytical oracle required'}
save('receipt-'.._VERSION:gsub(' ','-')..'.json',receipt)
assert(#failures==0,'Stage33 escaped corruptions: '..P.serialize(failures))
return receipt
