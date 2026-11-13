local P,H,V=require('pattern'),require('pattern_hash'),require('pattern_render')
local Tex=require('pattern_tex');local lfs=require('lfs')
local function read(path)local f=assert(io.open(path,'rb'));local b=f:read('*a');f:close();return b end
local source={};for name in lfs.dir('.')do
  if name:match('%.lua$') or name:match('^florilegium.*%.sty$') or name:match('^florilegium.*%.def$')then source[name]=read(name)end
end
local hashes={};for name,bytes in pairs(source)do hashes[name]=H.sha256(bytes)end
hashes['tools/check-pattern-tex.lua']=H.sha256(read('tools/check-pattern-tex.lua'))
hashes['tools/tex-inline-constraints.lua']=H.sha256(read('tools/tex-inline-constraints.lua'))
for name in lfs.dir('examples/patterns')do
  if name:match('%.recipe$')then local path='examples/patterns/'..name;hashes[path]=H.sha256(read(path))end
end
for _,name in ipairs({'periodic','micrography','gothic-spatial','penrose'})do
  local path='examples/cli/'..name..'.recipe';hashes[path]=H.sha256(read(path))
end
local digest=H.value('tex/check-source',hashes)
local destination='build/pattern-tex/'..digest..(PATTERN_TEST_VARIANT or '')
lfs.mkdir('build');lfs.mkdir('build/pattern-tex');lfs.mkdir(destination)
local outputs={};local checks=0
local function check(ok,message)assert(ok,message);checks=checks+1 end
local function reject(fn,message)local ok=pcall(fn);check(not ok,message)end
local function write(name,bytes)local f=assert(io.open(destination..'/'..name,'wb'));f:write(bytes);f:close();outputs[name]=H.sha256(bytes)end
local host={source=source,runtime=PATTERN_TEST_HOST or 'texlua'}
local adapter=Tex.new(host)
local function declare(name,path)return adapter:declare(name,read(path))end
local periodic=declare('periodic','examples/cli/periodic.recipe')
declare('same','examples/cli/periodic.recipe')
check(adapter.generations==1 and adapter.assets.same==periodic,'recipe aliases must reuse the validated generation')
periodic.registry.generate=function()error('unexpected shipout generation')end
local function page(index,logical)
  return {index=index,logical_number=logical,label='XLI',size={10,12},content={2,2,8,10},twoside=true,
    header_top=11,footer_bottom=1,running_regions={{2,10.5,8,11},{2,.5,8,1}},
    dimensions_sp={hoffset=65536,voffset=-65536},reservations=P.array(),
    anchors={{id='heading/1',role='heading',point={2.1,9.8},space='page'}}}
end
local odd=adapter:place('periodic',page(2,41),{region='outer'})
check(odd.crop[1]>8 and odd.view.transform[1]>0 and odd.view.transform[4]>0,'TeX odd text layout chooses its actual outer side without reflection')
check(odd.view.extensions.tex_document.physical_index==2 and odd.view.extensions.tex_document.printed_label=='XLI','physical index and printed label must remain distinct')
check(odd.view.extensions.tex_document.document.pages[1].number==2,'shared document context uses the shipped index')
local even=adapter:place('periodic',page(3,42),{region='outer'})
check(even.crop[3]<2,'TeX even text layout chooses the opposite actual margin')
check(adapter.generations==1,'shipout must not generate another instance')
check(P.serialize(periodic.result.instance)==periodic.result.bytes.instance and P.serialize(periodic.result.scene)==periodic.result.bytes.scene,'placement mutated cached semantic data')
local masks=page(4,7);masks.reservations={{1,1,2,5},{2,1,5,2}}
local protected=adapter:place('periodic',masks,{region='page',protect_text=false,padding=0})
check(#protected.view.protected_regions==2+#periodic.recipe.view.protected_regions
  and P.serialize(protected.view.protected_regions[1].bounds)==P.serialize(masks.reservations[1])
  and P.serialize(protected.view.protected_regions[2].bounds)==P.serialize(masks.reservations[2]),'irregular union or original recipe reservation lost')
write('protected.pdf',protected.pdf);write('protected.svg',V.svg(protected.plan));write('protected.view',protected.bytes.view)
reject(function()adapter:place('periodic',page(4,7),{region='content',padding=0})end,'fully protected content must fail')
reject(function()adapter:place('periodic',page(4,7),{region='invented'})end,'unsupported region must fail')
reject(function()adapter:place('periodic',page(4,7),{padding=-1})end,'negative padding must fail')
reject(function()adapter:place('periodic',page(4,7),{mirror=true})end,'unsupported mirror must fail')
reject(function()declare('periodic','examples/cli/periodic.recipe')end,'duplicate declaration must fail')
local penrose=declare('penrose','examples/patterns/penrose.recipe')
local options={region='page',spread='left',padding=0,protect_text=false}
reject(function()adapter:place('penrose',page(1,40),options)end,'spread cannot begin on actual odd page despite even logical label')
local left=adapter:place('penrose',page(2,41),options)
reject(function()adapter:finish()end,'unmatched left spread must fail')
options.spread='right'
reject(function()adapter:place('penrose',page(4,42),options)end,'nonadjacent physical pages must fail')
local right=adapter:place('penrose',page(3,42),options)
check(left.asset==right.asset and left.asset.instance_sha256==right.asset.instance_sha256,'spread changed source instance')
check(left.view.transform[1]==right.view.transform[1] and left.view.transform[5]-right.view.transform[5]==10,'spread global frame must differ by exactly one media width')
check(#right.spread_document.spreads==1 and right.spread_document.pages[2].number==3,'shared spread context not recorded')
adapter:finish()
write('spread-left.pdf',left.pdf);write('spread-right.pdf',right.pdf)
write('spread-left.svg',V.svg(left.plan));write('spread-right.svg',V.svg(right.plan))
local micro=declare('micrography','examples/cli/micrography.recipe')
local text=adapter:place('micrography',page(5,100),{region='content',protect_text=false,padding=0})
local old=V.plan(micro.result.scene,micro.result.instance,micro.result.view,micro.definition)
check(#text.plan.text==#old.text and #text.plan.text>0,'logical searchable text was lost')
for i,t in ipairs(text.plan.text)do check(t.text==old.text[i].text and t.transform[1]>0 and t.transform[4]>0,'text mirrored or changed')end
write('micrography.pdf',text.pdf);write('micrography.svg',V.svg(text.plan))
local hybrid=declare('hybrid','examples/patterns/hybrid.recipe')
check(hybrid.result.instance.extensions.celtic.attachment.port~=nil,'real botanical/knot attachment missing')
local placed=adapter:place('hybrid',page(6,19),{region='outer'})
check(#placed.scene.operations==#hybrid.result.scene.operations,'placement lost original semantic operations/selection')
write('hybrid.pdf',placed.pdf);write('hybrid.svg',V.svg(placed.plan))
local initial=declare('initial','examples/patterns/initial.recipe')
local initial_plan=adapter:plan('initial');check(#initial_plan.text>0,'semantic initial lost searchable text')
write('initial.pdf',V.pdf(initial_plan));write('initial.svg',V.svg(initial_plan))
local spatial=declare('spatial','examples/cli/gothic-spatial.recipe')
local projected=adapter:place('spatial',page(7,20),{region='content',protect_text=false,padding=0})
check(projected.view.derived and projected.view.validity=='visualization_only','3D projection lost its declared validity')
check(projected.asset.instance_sha256==spatial.instance_sha256,'spatial placement changed semantic curves')
write('spatial.pdf',projected.pdf);write('spatial.svg',V.svg(projected.plan))
local minimum_recipe=P.plain(require('pattern_recipe').decode(read('examples/cli/penrose.recipe')))
local source_adapter=Tex.new(host)
local source_asset=source_adapter:declare('measure',require('pattern_recipe').encode(minimum_recipe))
local source_plan=source_adapter:plan('measure')
local minimum=require('pattern_planner').check_render_requirements(source_plan,{minimum_stroke=1e-12}).minimum_stroke
minimum_recipe.view.extensions.document_planning.options.minimum_stroke=minimum*.9
local constrained=adapter:declare('minimum',require('pattern_recipe').encode(minimum_recipe))
local expanded=adapter:place('minimum',page(8,31),{region='content',protect_text=false,padding=0})
check(expanded.record.validation.print_requirements.minimum_stroke_lower_bound>=minimum*.9,'enlarged physical view lost source print requirements')
reject(function()adapter:place('minimum',page(8,31),{region='outer'})end,'fitting must not silently violate the source minimum stroke')
check(P.serialize(constrained.result.instance)==constrained.result.bytes.instance,'failed fit changed cached source instance')
local _,_,inline=adapter:inline('minimum',0)
check(inline.scale==1 and inline.print_requirements.minimum_stroke_lower_bound>=minimum*.9,'natural inline lost physical print minima')
local _,_,larger=adapter:inline('minimum',inline.width*2)
check(larger.print_requirements.minimum_stroke_lower_bound==inline.print_requirements.minimum_stroke_lower_bound*2,'inline print evidence must use physical units')
reject(function()adapter:inline('minimum',inline.width/10)end,'inline shrinking must preserve declared stroke minimum')
reject(function()adapter:inline('minimum',-1)end,'negative inline width accepted')
reject(function()adapter:inline('minimum',0/0)end,'nonfinite inline width accepted')
local text_recipe=dofile('tools/tex-inline-constraints.lua').text(.001)
adapter:declare('text-minimum',require('pattern_recipe').encode(text_recipe))
local _,_,text_inline=adapter:inline('text-minimum',0)
check(text_inline.print_requirements.minimum_text_size_lower_bound>=.001,'natural inline text constraint was not checked')
reject(function()adapter:inline('text-minimum',.000001)end,'inline shrinking must preserve declared text minimum')
local receipt={source_digest=digest,checks=checks,outputs=outputs,unique_generations=adapter.generations,
  physical_views=adapter.views,source_files=hashes,shipped_index_test={physical=2,logical=41,label='XLI'},
  original_scene_selection_preserved=true,optimizer_at_shipout=false}
local f=assert(io.open(destination..'/receipt.json','wb'));f:write(P.serialize(receipt));f:close()
print('Shared TeX adapter checks',checks,digest)
