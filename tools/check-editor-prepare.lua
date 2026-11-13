local P,Q,R,H,V,E,O=require('pattern'),require('pattern_recipe'),require('pattern_registry'),require('pattern_hash'),require('pattern_render'),require('pattern_editor'),require('pattern_output_style')
local fs=require('lfs');local source={};for name in fs.dir('.')do if name:match('%.lua$')then local f=assert(io.open(name,'rb'));source[name]=f:read('*a');f:close()end end
local f=assert(io.open('examples/cli/periodic.recipe','rb'));local base=Q.decode(f:read('*a'));f:close()
local reg=R.new();local d=require('pattern_periodic').register(reg)
local env=Q.environment({revision='working/editor-prepare',files={construction=source,style={},view={},renderer={}}},{lua=_VERSION,host=PATTERN_TEST_HOST or'texlua/editor-prepare'},{id=V.VERSION,version='1'})
local first=Q.execute(base,reg,env);assert(first.record.status=='complete',P.serialize(first.record.diagnostics))
local checks=0;local function check(ok,why)assert(ok,why);checks=checks+1 end
for _,name in ipairs{'parameters','inputs','style'}do
 for _,value in ipairs{false,P.array()}do local edit={schema_version=1};edit[name]=value;check(not pcall(E.apply,base,edit),'non-object edit ignored:'..name)end
end
for _,name in ipairs{'crop','protected_regions','page_size'}do
 for _,value in ipairs{false,{}}do local edit={schema_version=1};edit[name]=value;check(not pcall(E.apply,base,edit),'non-array edit ignored:'..name)end
end
local touched=false;local host={read=function()touched=true;return Q.encode(base)end}
check(not pcall(require('pattern_cli_core').dispatch,{schema_version=1,command='validate',edits=false},host)and not touched,'false edits bypassed native request validation')
check(not pcall(require('pattern_cli_core').dispatch,{schema_version=1,command='capabilities',edits={schema_version=1}},host)and not touched,'unsupported edit command silently ignored intent')
local Parse=require('pattern_parse');local large='{"payload":"'..string.rep('x',2*1024*1024)..'"}'
check(not pcall(Parse.decode,large),'recipe byte guard was weakened for editor instances')
check(#Parse.instance(large).payload==2*1024*1024,'instance transport did not admit bounded large payload')
for _,invalid in ipairs{'{"id":1,"id":2}','[1e999]','[null]',string.rep('[',62)..'0'..string.rep(']',62)}do check(not pcall(Parse.instance,invalid),'instance route bypassed strict JSON validation')end
local next_recipe,receipt=E.apply(base,{schema_version=1,crop={.2,.2,2.8,2.4},protected_regions=P.array(),style={output_profile={schema_version=1,mode='monochrome'}}})
check(next_recipe.view.extensions.document_planning~=nil and next_recipe.design.extensions.planning_generation~=nil,'native planning metadata was stripped')
check(not receipt.structural_change and Q.structural_digest(next_recipe)==Q.structural_digest(base),'crop/color changed native construction')
local called=false;reg.generate=function()called=true;error('paint/view edit regenerated source')end
local revised=Q.revise(next_recipe,base,first.instance,first.record,reg,env)
check(revised.record.status=='complete','planned revision failed:'..P.serialize(revised.record.diagnostics))
check(revised.bytes.instance==first.bytes.instance and not called,'planned revision changed source or regenerated')
local plan=V.plan(revised.scene,revised.instance,revised.view,d);local paints=0
for op in V.operations(plan)do if op.op=='path'then check(op.paint.color_space=='gray','non-gray paint in print profile');for _,k in ipairs{'fill','stroke'}do if op.paint[k]then check(#op.paint[k]==1,'print paint retained RGB channels');paints=paints+1 end end end end
local pdf=V.pdf(plan);check(not pdf:find(' rg',1,true)and not pdf:find(' RG',1,true)and paints>0,'PDF print profile did not use gray operators')
local resized,change=E.apply(base,{schema_version=1,page_size={21,29.7}})
check(change.structural_change and resized.view.crop[3]==21 and resized.view.crop[4]==29.7,'media resize did not use native document context')
local denied=Q.revise(resized,base,first.instance,first.record,reg,env);check(denied.record.status=='failed'and not called,'larger query was silently treated as view-only')
for _,invalid in ipairs{{schema_version=2},{schema_version=1,unknown=true},{schema_version=1,style={output_profile={schema_version=2,mode='monochrome'}}}}do check(not pcall(E.apply,base,invalid),'invalid edit/profile accepted')end
local asset={kind='vector_asset',schema_version=1,unit='cm',operations={{op='path',commands={{'M',0,0},{'L',1,0},{'L',1,1},{'Z'}},paint={fill={.2,.4,.6}}}}};local content=P.serialize(asset)
local scene=P.plain(first.scene);scene.operations={{op='symbol',semantic_ref=first.instance.structures.tiling.cells[1].id,resource_ref='editor-symbol',transform={1,0,0,1,0,0}}};scene.resources={{id='editor-symbol',kind='symbol',unit='cm',bounds={0,0,1,1},variants={scene={encoding='utf8',content=content,sha256=H.sha256(content)}}}}
scene=P.scene(scene,first.instance,first.view,d)
local transformed=O.apply(scene,{schema_version=1,mode='monochrome'});transformed=P.scene(transformed,first.instance,first.view,d)
local resource=transformed.resources[1];local decoded=require('pattern_draw').asset(resource)
check(resource.variants.scene.sha256==H.sha256(resource.variants.scene.content)and resource.variants.scene.sha256~=H.sha256(content),'styled symbol content hash not updated')
check(P.serialize(decoded.operations[1].commands)==P.serialize(asset.operations[1].commands),'symbol recoloring changed geometry')
check(decoded.operations[1].paint.color_space=='gray'and #decoded.operations[1].paint.fill==1,'encoded symbol escaped grayscale transformation')
local white={operations={{op='path',paint={fill={1,1,1}}}},resources={}}
local tint=O.apply(white,{schema_version=1,mode='palette',fill={.1,.4,.2},stroke={.2,.1,.1}})
check(P.serialize(tint.operations[1].paint.fill)==P.serialize({1,1,1}),'palette painted over white gaps')
for _,name in ipairs{'build','build/editor-prepare'}do fs.mkdir(name)end
local result={checks=checks,actual_lua=_VERSION,source_digest=env.source.digest,native_document_plan_preserved=true,source_instance_sha256=H.sha256(first.bytes.instance),revised_instance_sha256=H.sha256(revised.bytes.instance),gray_paints=paints,pdf_devicegray_verified=true,encoded_symbol_geometry_preserved=true,scope='Shared editor planner/color API; complete UI/nativeCI acceptance remains pending'}
local out=assert(io.open('build/editor-prepare/receipt-'.._VERSION:gsub(' ','-')..'.json','wb'));out:write(P.serialize(result));out:close();print('Editor native preparation/color checks',checks,_VERSION);return result
