local P,Q,E,C,H,V=require('pattern'),require('pattern_recipe'),require('pattern_editor'),require('pattern_cli_core'),require('pattern_hash'),require('pattern_render')
local fs=require('lfs');local function read(p)local f=assert(io.open(p,'rb'));local b=f:read('*a');f:close();return b end
local files={};for name in fs.dir('.')do if name:match('%.lua$')then files[name]=read(name)end end;files['tools/check-floral-editor-seed.lua']=read('tools/check-floral-editor-seed.lua')
local env=Q.environment({revision='working/floral-editor-seed34',files={construction=files,style={},view={},renderer={}}},{lua=_VERSION,host=PATTERN_TEST_HOST or 'texlua/floral-editor-seed34'},{id=V.VERSION,version='1'})
local checks=0;local rows=P.array();local function check(ok,why)assert(ok,why);checks=checks+1 end
for _,mode in ipairs{'authored','grown'}do
 local original=Q.decode(read('examples/cli/botanical-'..mode..'.recipe'))
 local edited,receipt=E.apply(original,{schema_version=1,seed=102})
 check(edited.design.seed==102 and edited.design.extensions.legacy_geometry.seed==102,'Floral design/host seed mismatch:'..mode)
 check(original.design.seed~=102 and original.design.extensions.legacy_geometry.seed==original.design.seed,'Edit mutated original floral recipe')
 check(receipt.structural_change,'Seed edit did not invalidate structural cache')
 -- Use a physically scaled native host for bounded positive generation.
 local small=P.plain(edited);local g=small.design.extensions.legacy_geometry
 for _,key in ipairs{'pw','ph','textleft','textright','ytop','ybot','colright','headrule','footy','spilly','actual_left','actual_right'}do if g[key]then g[key]=g[key]*.25 end end
 small=Q.new(small);local registry=C.registry(small.definition.id);local generated=Q.execute(small,registry,env)
 check(generated.record.status=='complete','Edited floral seed failed actual generation:'..mode..':'..P.serialize(generated.record.diagnostics))
 check(generated.instance.provenance.seed==102 and generated.instance.extensions.legacy.geometry.seed==102,'Generated floral seed differs from edited design')
 local saved=registry.generate;registry.generate=function()error('Floral seed replay regenerated')end
 local replay=Q.replay(small,generated.instance,generated.record,registry,env);registry.generate=saved
 check(replay.record.status=='complete'and replay.bytes.instance==generated.bytes.instance and replay.bytes.scene==generated.bytes.scene,'Floral edited instance failed exact replay')
 rows[#rows+1]={mode=mode,seed=102,instance_sha256=generated.record.outputs[1].sha256,scene_sha256=generated.record.outputs[2].sha256,status='passed'}
end
fs.mkdir('build');fs.mkdir('build/floral-editor-seed');local result={status='passed',checks=checks,actual_lua=_VERSION,source_digest=env.source.digest,source_files_sha256=P.plain(env.source.files.construction),cases=rows}
local f=assert(io.open('build/floral-editor-seed/receipt-'.._VERSION:gsub(' ','-')..'.json','wb'));f:write(P.serialize(result));f:close();print('Actual authored/grown editor seed checks',checks,_VERSION);return result
