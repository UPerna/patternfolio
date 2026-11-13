-- Actual PDF/SVG conformance fixtures; run from the repository root.
local P,E,R,V=require("pattern"),require("pattern_examples"),require("pattern_registry"),require("pattern_render")
local H,A=require("pattern_hash"),require("pattern_artifact")
local lfs=require("lfs");local count=0
local function check(ok,why)assert(ok,why);count=count+1 end
local function reject(fn)check(not pcall(fn),"expected unsupported/invalid scene rejection")end
local function read(p)local f=assert(io.open(p,"rb"));local s=assert(f:read("*a"));assert(f:close());return s end
local files={"pattern.lua","pattern_json.lua","pattern_parse.lua","pattern_hash.lua","pattern_registry.lua","pattern_geometry.lua","pattern_predicates.lua","pattern_exact.lua","pattern_curves.lua","pattern_bounds.lua","ink.lua","flora.lua","pdfwriter.lua","pattern_draw.lua","pattern_render.lua","pattern_ink.lua","pattern_bytes.lua","pattern_artifact.lua","pattern_examples.lua","tools/scenecheck.lua","tools/scene_oracle.py","docs/validation/fixtures/scene-font.json"}
files[#files+1]="docs/validation/fixtures/scene-v1-digests.json"
local golden=require("pattern_parse").decode(read("docs/validation/fixtures/scene-v1-digests.json"))
local source={};for _,f in ipairs(files)do source[#source+1]={path=f,sha256=H.sha256(read(f):gsub("\r\n","\n"))}end
local digest=H.sha256(P.serialize(source));local root="build/scenes/"..digest
local function dir(p)local ok=lfs.mkdir(p);if not ok then assert(lfs.dir(p),"output directory unavailable")end end
dir("build");dir("build/scenes");dir(root)
local atomic=root.."/atomic-probe.bin"
check(A.write(atomic,"\0\255PDF\n")==H.sha256("\0\255PDF\n"),"binary artifact hash")
check(A.write(atomic,"\0\255PDF\n")==H.sha256(read(atomic)),"identical immutable artifact replay")
reject(function()A.write(atomic,"different")end);check(read(atomic)=="\0\255PDF\n","conflict damaged prior artifact")
assert(lfs.mkdir(atomic..".lock"));reject(function()A.write(atomic,"\0\255PDF\n")end);assert(lfs.rmdir(atomic..".lock"))
local unfinished=root.."/unfinished-probe.bin";local f=assert(io.open(unfinished..".pending","wb"));assert(f:write("unfinished"));assert(f:close())
reject(function()A.write(unfinished,"new")end);check(read(unfinished..".pending")=="unfinished","unfinished evidence lost");assert(os.remove(unfinished..".pending"))
local registry,defs=E.registry();local fixtures={}
local function context()return R.context({seed=7,source={revision="scene-fixture"}})end
local function emit(name,x,v,d,s)
  local before=P.serialize(x);local plan=V.plan(s,x,v,d);local svg,pdf=V.svg(plan),V.pdf(plan)
  check(H.sha256(pdf)==golden.fixtures[name].pdf_sha256,"single-page PDF differs from independently verified06 output")
  check(H.sha256(svg)==golden.fixtures[name].svg_sha256,"single-page SVG differs from independently verified06 output")
  check(P.serialize(x)==before,"render mutated semantic instance")
  check(svg==V.svg(plan) and pdf==V.pdf(plan),"render bytes not deterministic")
  check(svg:find('<path ',1,true) and not svg:find('<image',1,true),"SVG paths required, raster prohibited")
  check(pdf:sub(1,8)=="%PDF-1.5" and not pdf:find('/Subtype /Image',1,true),"PDF vectors required, raster prohibited")
  local outputs={};for ext,data in pairs({pdf=pdf,svg=svg,scene=P.serialize(s),plan=P.serialize(plan)})do outputs[ext]={path=root.."/"..name.."."..ext,sha256=A.write(root.."/"..name.."."..ext,data)}end
  fixtures[#fixtures+1]={name=name,outputs=outputs,bounds=P.plain(plan.bounds),protected_regions=P.plain(v.protected_regions)}
  return plan
end
for _,name in ipairs({"floral","graph","tiling"})do
  local d=defs[name];local result,err=registry:generate(d.id,E.specification(d),context());assert(result,err)
  local x=result.instance;local crop=name=="floral" and {1,1,5,5} or {-0.15,-0.15,2.15,1.15};local v=E.view(x,d,crop)
  local s=registry:lower(d.id,x,v,{},context())
  if name=="floral"then
    s=P.plain(s);s.operations[2]=P.plain(s.operations[1]);s.operations[2].transform={0.4,0,0,0.4,0.5,0.5};s=P.scene(s,x,v,d)
  elseif name=="graph"then
    local dd=P.plain(d);dd.capabilities={"graph","strands"};d=P.definition(dd)
    local xx=P.plain(x);xx.structures.strands={components={{id="strand",closed=false,alternating=false,endpoints={"port/a","port/b"},encounters=P.array()}},crossings=P.array(),ports={{id="port/a",component="strand",point={0,0.2}},{id="port/b",component="strand",point={2,0.2}}}};x=P.instance(xx,d);v=E.view(x,d,crop)
    s=P.plain(s);s.operations[#s.operations+1]={op="path",semantic_ref="strand",commands={{"M",0,0.2},{"C",0.5,0.8,1.5,0.8,2,0.2}},paint={stroke={0.6,0.1,0.1},stroke_width=0.03,cap="round"}};s=P.scene(s,x,v,d)
  end
  local plan=emit(name,x,v,d,s)
  if name=="tiling"then
    local counts={};for _,o in ipairs(plan.operations)do if o.op=="path" and o.paint.stroke then counts[o.semantic_ref]=(counts[o.semantic_ref] or 0)+1 end end
    local edges=0;for _,n in pairs(counts)do check(n==1,"tile seam stroked more than once");edges=edges+1 end;check(edges==7 and counts["tile/shared"]==1,"shared global seam missing")
  end
end
local function custom(name,structures,capabilities,crop,protected,ops,resources,order)
  local d=P.plain(defs.graph);d.id="scene/"..name;d.capabilities=capabilities;d=P.definition(d)
  local x=P.instance({id=d.id.."/instance",definition_ref={id=d.id,version=d.version},frame={id="world",dimension=2,unit="cm",handedness="right",origin={0,0}},structures=structures,provenance={generator=d.id,generator_version=d.version,seed=7,construction="explicit stage06 fixture"},extensions={}},d)
  local v=P.plain(E.view(x,d,crop));v.protected_regions=protected or P.array();v=P.view(v,x,d)
  local s=P.scene({id=d.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=resources or P.array(),reading_order=order},x,v,d)
  return emit(name,x,v,d,s),s,x,v,d
end
local growth={growth={nodes={{id="root",point={0,0},motif="fixture"}},roots={"root"}}}
local function rect(a,b,c,d)return {{"M",a,b},{"L",c,b},{"L",c,d},{"L",a,d},{"Z"}}end
local function path(commands,paint,transform)return {op="path",semantic_ref="root",commands=commands,paint=paint,transform=transform}end
local commands=rect(0,0,6,4);local hole=rect(1,1,2,2);for _,c in ipairs(hole)do commands[#commands+1]=c end
local rings=rect(4.5,0.6,5.7,1.8);for _,c in ipairs(rect(4.8,0.9,5.4,1.5))do rings[#rings+1]=c end
custom("clipstress",growth,{"growth"},{0,0,6,4},{{bounds={2.5,0.7,3.5,2.8},role="protected_content"},{bounds={3,1.7,4.3,3.2},role="protected_content"}}, {
  path(rect(-1,-1,7,5),{fill={0.8,0.9,0.95}}),
  path(commands,{fill={0.2,0.5,0.8},fill_rule="evenodd",opacity=0.7}),
  {op="push_clip",commands=rect(0,0,2,1.5),fill_rule="nonzero",transform={1,0.3,0.4,1,0.5,0.4}},
  {op="push_clip",commands=rect(0.8,0.6,3,2),fill_rule="nonzero"},
  path(rect(-1,-1,7,5),{fill={0.9,0.2,0.1},blend="multiply",opacity=0.6}),{op="pop_clip"},{op="pop_clip"},
  path({{"M",0,0.1},{"L",6,0.1}}, {stroke={0,0,0},stroke_width=0.2,cap="square",dash={array={0.3,0.1},phase=0.13}}),
  path({{"M",0,0.3},{"L",6,0.3}}, {stroke={0.8,0,0},stroke_width=0.05,cap="butt",dash={array={0.3,0.2},phase=0.13}}),
  path(rings,{fill={0,0.4,0.1},fill_rule="evenodd"}),
  path({{"M",0.2,0},{"L",0.8,1},{"L",1.5,0.2}}, {stroke={0.1,0.2,0.1},stroke_width=0.06,join="miter",miter_limit=4}, {1,0.1,0.2,1,4,2})})
custom("mono",growth,{"growth"},{0,0,3,2},nil,{
  path(rect(0,0,3,2),{fill={0.8},color_space="gray"}),
  path(rect(0.3,0.3,2.7,1.7),{fill={0.2},stroke={0},color_space="gray",stroke_width=0.05,opacity=0.7,blend="multiply"})})
local font=require("pattern_parse").decode(read("docs/validation/fixtures/scene-font.json"))
local plan,s,x,v,d=custom("text",{text={runs={{id="run/first",text="Aα",direction="ltr"},{id="run/second",text="αA",direction="ltr"}},reading_order={"run/second","run/first"}}},{"text"},{0,0,4,3},nil,{
  {op="text",semantic_ref="run/first",font_ref=font.id,text="Aα",origin={0.4,0.5},size=0.8,glyphs={{glyph_ref="glyph/65",offset={0,0}},{glyph_ref="glyph/945",offset={0.7,0.1}}},paint={fill={0.1,0.2,0.4}}},
  {op="text",semantic_ref="run/second",font_ref=font.id,text="αA",origin={0.6,1.8},size=0.9,glyphs={{glyph_ref="glyph/945",offset={0,0}},{glyph_ref="glyph/65",offset={0.7,0}}},paint={fill={0.3,0.1,0.1}},transform={1,0.1,0,1,0,0}}
},{font},{"run/second","run/first"})
check(plan.text[1].semantic_ref=="run/second","logical text order lost")
local bad=P.plain(s);bad.operations[1].glyphs[1].glyph_ref="missing";reject(function()V.plan(bad,x,v,d)end)
bad=P.plain(s);bad.reading_order={"run/first","run/second"};reject(function()V.plan(bad,x,v,d)end)
bad=P.plain(s);bad.operations[1].text="?";reject(function()V.plan(bad,x,v,d)end)
bad=P.plain(s);bad.resources[1].variants.opentype.sha256=string.rep("0",64);reject(function()V.plan(bad,x,v,d)end)
local receipt={stage="06",status="local_render_checks_passed",host=PATTERN_TEST_HOST or _VERSION,source_digest=digest,source=source,fixtures=fixtures,checks=count}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(receipt))
print("scenecheck: "..count.." checks passed; six actual PDF/SVG fixtures in "..root)
return receipt
