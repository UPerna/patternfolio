local P,Q,R,E,H=require("pattern"),require("pattern_recipe"),require("pattern_registry"),
  require("pattern_examples"),require("pattern_hash")
local fs=require("lfs")
local reg,defs=E.registry()
local source={}
for name in fs.dir(".") do
  if name:match("%.lua$") then
    local f=assert(io.open(name,"rb"))
    source[name]=f:read("*a"):gsub("\r\n","\n");f:close()
  end
end
do
  local f=assert(io.open("tools/check-cli-core.lua","rb"))
  source["tools/check-cli-core.lua"]=f:read("*a"):gsub("\r\n","\n");f:close()
end
local legacy_fixture
do
  local name="docs/validation/fixtures/escher-cross-host.json"
  local f=assert(io.open(name,"rb"))
  source[name]=f:read("*a");f:close()
  legacy_fixture=require("pattern_parse").decode(source[name])
end
local env=Q.environment({revision="working/cli-core",files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=require("pattern_render").VERSION,version="1"})
local d=defs.graph
local recipe=Q.from_specification(d,E.specification(d),{
  unit="cm",transform={1,0,0,1,0,0},crop={0,0,3,2},protected_regions=P.array(),
  derived=false,validity="construction_preserved"},2)
local first=Q.execute(recipe,reg,env)
assert(first.record.status=="complete")
local generator_called=false
reg.generate=function() generator_called=true;error("optimizer must stay disabled during replay") end
local checks=0
local function check(ok,why) assert(ok,why);checks=checks+1 end
local replay=Q.replay(recipe,first.instance,first.record,reg,env)
check(replay.record.status=="complete","stored replay "..P.serialize(replay.record.diagnostics))
check(not generator_called,"replay invoked generator")
check(replay.bytes.instance==first.bytes.instance and replay.bytes.scene==first.bytes.scene,"replay changed geometry")
check(replay.record.lineage[1].parent_ref==first.record.id,"missing parent lineage")
check(replay.keys.structure~=first.keys.structure,"replay cache identity omits the stored instance")
local altered=P.plain(first.instance)
altered.structures.graph.vertices[1].point[1]=.1
local bad=Q.replay(recipe,altered,first.record,reg,env)
check(bad.record.status=="failed" and #bad.record.outputs==0,"tampered cached instance")
local incomplete=P.plain(first.record)
incomplete.status="failed"
incomplete.diagnostics={"interrupted"}
bad=Q.replay(recipe,first.instance,incomplete,reg,env)
check(bad.record.status=="failed" and #bad.record.outputs==0,"incomplete parent record")
local cancel=Q.replay(recipe,first.instance,first.record,reg,env,{cancelled=function()return true end})
check(cancel.record.status=="cancelled" and #cancel.record.outputs==0,"cancelled replay")
bad=Q.replay(recipe,first.instance,first.record,reg,env,{limits={objects=0,operations=0,bytes=0}})
check(bad.record.status=="failed" and #bad.record.outputs==0,"exhausted replay")
local wrong=P.plain(recipe)
wrong.design.seed=8
bad=Q.replay(wrong,first.instance,first.record,reg,env)
check(bad.record.status=="failed","cached recipe binding")
local invalid=P.plain(first.instance)
invalid.structures.graph.edges[1].to="absent"
check(not pcall(reg.validate,reg,d.id,invalid,R.context({seed=7,source={revision="cli-test"}})),
  "structural validation accepted a dangling edge")
check(not generator_called,"failure handling invoked generator")
local escher=require("pattern_escher")
check(escher.validate(legacy_fixture).ok,"previous native Escher witness rejected")
for _,field in ipairs({"baseline","score","errors","baseline_errors"}) do
  local changed=P.plain(legacy_fixture)
  local solver=changed.extensions.escher.solver
  if type(solver[field])=="table" then solver[field][1]=solver[field][1]+1e-5
  else solver[field]=solver[field]+1e-5 end
  check(not pcall(escher.validate,changed),"incorrect cached metric accepted")
end
local folder="build/cli-core/"..env.source.digest
for _,path in ipairs{"build","build/cli-core",folder} do fs.mkdir(path) end
require("pattern_artifact").write(folder.."/receipt-".._VERSION:gsub(" ","-")..".json",
  P.serialize({checks=checks,source_digest=H.value("cli-core/source",env.source),optimizer_calls=0}))
print("CLI core replay checks",checks)
