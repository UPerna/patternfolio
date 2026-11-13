local P,R,Q=require("pattern"),require("pattern_registry"),require("pattern_recipe")
local M,F,V,H,A=require("pattern_micrography"),require("pattern_micro_field"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local Parse=require("pattern_parse")
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local bytes=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name],hashes[name]=bytes,H.sha256(bytes)
end
local font_path="docs/validation/fixtures/micrography-font.json"
for n in fs.dir(".") do if n:match("%.lua$") then read(n) end end
read("tools/micrographycheck.lua");read("tools/micrography_oracle.py");read(font_path)
local font=Parse.decode(source[font_path])
local digest=H.value("micrography/source",hashes)
local folder="build/micrography/"..digest..(PATTERN_TEST_VARIANT or "")
for _,p in ipairs{"build","build/micrography",folder} do fs.mkdir(p) end
local outputs={}
local function write(name,bytes) outputs[name]=A.write(folder.."/"..name,bytes) end
local reg=R.new()
local d=M.register(reg)
local env=Q.environment({revision="working/micrography/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},{id=V.VERSION,version="1"})
local checks=0
local function check(ok,msg) assert(ok,msg);checks=checks+1 end
local b={0,0,13,7}
local panel={{.5,.52},{12.4,1.2},{12.3,6.4},{.8,5.72}}
local skew={{.5,.55},{12.45,2.65},{11.85,6.07},{.7,6.24}}
local latin="A fine line follows the lift of the shore. Its small letters hold a quiet thought while the field guides each word. The page keeps every mark in order, from the first word to the last. Along the bank the water folds back, and the light finds another way. Beyond the bend a narrow path carries us past the reeds. Each step leaves a quiet space for the next. We follow the curve until the river opens and the far bank comes into view."
local combined="Café light flows over the field. A fine river holds the blue of the sky. At the café we read slowly, and the last line carries the first thought home. The folded shore and the open field share a single breath. Farther down the river, a small bridge marks the place where the current turns. The letters keep their rhythm even as the banks draw closer."
local greek="ΤΟ ΦΩΣ ΓΡΑΦΕΙ ΣΧΗΜΑΤΑ. Ο ΠΟΤΑΜΟΣ ΡΕΕΙ ΚΑΙ ΤΟ ΝΕΡΟ ΛΑΜΠΕΙ. Ο ΟΥΡΑΝΟΣ ΚΑΙ Η ΓΗ ΚΡΑΤΟΥΝ ΤΟ ΦΩΣ. ΤΟ ΦΩΣ ΓΡΑΦΕΙ ΣΧΗΜΑΤΑ ΣΤΟ ΝΕΡΟ. Η ΟΧΘΗ ΑΛΛΑΖΕΙ ΚΑΙ Η ΣΚΙΑ ΠΕΦΤΕΙ ΑΡΓΑ. Ο ΑΝΕΜΟΣ ΠΕΡΝΑ ΠΑΝΩ ΑΠΟ ΤΟ ΝΕΡΟ ΚΑΙ ΤΟ ΦΩΣ ΜΕΝΕΙ."
local function recipe(name,text,region,params,fixed,crop)
  local limits={objects=85000,operations=20000000,bytes=64*1024*1024}
  return Q.from_specification(d,{id="micrography/"..name,definition_ref={id=d.id,version=d.version},seed=24,
    parameters=params or {size=.34},inputs={text=text,panel=region,font=font,fixed=fixed},style={},constraints={},
    budget=limits,document={unit="cm",bounds=b,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=crop or b,protected_regions=P.array(),derived=false,
      validity="construction_preserved"},2)
end
local function run(q)
  return Q.execute(Q.decode(Q.encode(q)),reg,env)
end
local function build(name,text,region,params,fixed)
  local q=recipe(name,text,region,params,fixed)
  local r=run(q)
  assert(r.record.status=="complete",name..": "..P.serialize(r.record.diagnostics))
  local x=r.instance
  local e=x.extensions.micrography
  local runs=x.structures.text.runs
  check(#runs>=6 and #e.clusters>50,name.." insufficient layout")
  check(e.field.labels.energy<e.field.labels.all_aligned,name.." no objective improvement")
  check(e.field.residual<1e-8 and e.field.min_representation_x>.15,name.." uncertified field")
  check(P.serialize(run(q).instance)==P.serialize(x),name.." replay")
  local plan=V.plan(r.scene,x,r.view,d)
  write(name..".recipe",Q.encode(q));write(name..".instance",P.serialize(x))
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
  print(name,#runs,#e.clusters,e.field.labels.mask,e.field.labels.energy,e.field.min_representation_x)
  return e
end
local a=build("latin",latin,panel,{size=.34})
local c=build("combining",combined,skew,{size=.35},{{1,1},{4,0}})
local g=build("greek",greek,panel,{size=.38,omega=.9})
local combining,ligatures=0,0
for _,v in ipairs(c.clusters) do if #v>1 then combining=combining+1 end end
for _,r in ipairs(c.positions) do
  for _,v in ipairs(r.spans) do if v[2]>v[1] then ligatures=ligatures+1 end end
end
check(combining==2 and ligatures>=3,"combining or ligature route not exercised")
check(c.field.labels.samples[1].label==1 and c.field.labels.samples[4].label==0,"fixed boundary controls not enforced")
local function failure(name,q,code)
  local r=run(q)
  check(r.record.status~="complete" and P.serialize(r.record.diagnostics):find(code,1,true)~=nil,
    name..": "..P.serialize(r.record.diagnostics))
  return {diagnostics=P.plain(r.record.diagnostics),solver=r.record.extensions and P.plain(r.record.extensions.solver) or nil}
end
local failures={}
failures.space=failure("space",recipe("space",latin,{{.3,.5},{4,.7},{4,2.1},{.4,1.9}},{size=.34}),"insufficient_space")
failures.size=failure("size",recipe("size",latin,panel,{size=.24,min_size=.33}),"legibility")
failures.script=failure("script",recipe("script","A line שלום.",panel,{size=.34}),"unsupported-script")
failures.budget=failure("budget",recipe("budget",latin,panel,{size=.34,iterations=1}),"field-budget")
failures.crop=failure("crop",recipe("crop",latin,panel,{size=.34},nil,{2,2,9,5}),"crop-would-hide-text")
write("failures.json",P.serialize(failures))
A.write(folder.."/receipt.json",P.serialize({stage="24",source_digest=digest,checks=checks,outputs=outputs,
  combining=combining,ligatures=ligatures}))
print("Micrography checks passed",checks,digest)
