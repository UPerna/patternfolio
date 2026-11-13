local P,R,Q,E=require("pattern"),require("pattern_registry"),require("pattern_recipe"),require("pattern_examples")
local F,C,V,H,A=require("pattern_hat"),require("pattern_bounded_tiles"),require("pattern_render"),
  require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local Parse=require("pattern_parse")
local reference="docs/validation/fixtures/hat-reference-hashes.json"
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local data=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name]=data;hashes[name]=H.sha256(data)
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
for _,name in ipairs{reference,"tools/hatcheck.lua","tools/hat_oracle.py"} do read(name) end
local digest=H.value("hat/source",hashes)
local root="build/hat/"..digest
for _,path in ipairs{"build","build/hat",root} do fs.mkdir(path) end
local output={}
local function write(name,data) output[name]=A.write(root.."/"..name,data) end
local function write_build(name,record)
  write(name..".solver.json",P.serialize({status=record.status,outputs=#record.outputs,
    solver=P.plain(record.extensions.solver),diagnostics=P.plain(record.diagnostics)}))
  A.write(root.."/"..name.."-".._VERSION:gsub(" ","-")..".build.json",P.serialize(record))
end
local checks=0
local function check(ok,message) assert(ok,message);checks=checks+1 end
local reg=R.new()
local d=F.register(reg)
local solver_clock=0
local solver=C.register(reg,function() solver_clock=solver_clock+.001;return solver_clock end)
local frame={id="hat/world",origin={0,0},unit="cm",dimension=2,handedness="right"}
local limits={objects=25000,operations=400000,bytes=64*1024*1024}
local function ctx()
  return R.context({seed=18,source={revision="working/hat/"..digest},frame=frame,limits=limits})
end
local function build(name,which,depth,box,whole)
  local result,e=reg:generate(d.id,{id="fixture/"..name,definition_ref={id=d.id,version=d.version},
    seed=18,parameters={root=which,depth=depth,kite_edge=.16,whole_root=whole},
    constraints={},inputs={},style={},budget=limits,document={unit="cm",bounds=box,protected_regions=P.array()}},ctx())
  assert(result,e and P.serialize(e))
  return result.instance
end
local all={}
local whole_box={2.6,-.2,13.8,10.8}
local kite_box={.7,-.2,5.2,4.2}
local references=Parse.decode(source[reference])
for _,r in ipairs(references) do
  local name=r.root..r.depth
  local box=name=="H3" and whole_box or (name=="H2" and kite_box or {-1,-1,15,12})
  local x=build(name,r.root,r.depth,box,true)
  local p=x.extensions.hat.certificate
  check(p.reference_hash==r.hash and p.tiles==r.count and p.reflected==r.reflected,"HatViz cluster mismatch: "..name)
  all[name]=P.plain(p)
  if name=="H3" or name=="H2" then all[name].instance=x end
end
local function export(name,x,box,style)
  local v=E.view(x,d,box)
  local scene=reg:lower(d.id,x,v,style or {},ctx())
  local plan=V.plan(scene,x,v,d)
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
  return plan
end
local whole,detail=all.H3.instance,all.H2.instance
all.H3.instance=nil;all.H2.instance=nil
write("cluster-certificates.json",P.serialize(all))
write("whole.instance",P.serialize(whole))
write("detail.instance",P.serialize(detail))
export("whole",whole,whole_box)
export("detail-kites",detail,kite_box,{display="kites"})
local box_a,box_b={4,1.8,9.2,6.8},{6.8,4,12,8.4}
local a,b=build("crop-a","H",3,box_a,false),build("crop-b","H",3,box_b,false)
export("crop-a",a,box_a);export("crop-b",b,box_b)
write("crop-a.instance",P.serialize(a));write("crop-b.instance",P.serialize(b))
local old={}
for _,c in ipairs(a.structures.tiling.cells) do old[c.id]=c end
local shared=0
for _,c in ipairs(b.structures.tiling.cells) do
  if old[c.id] then
    assert(P.serialize(old[c.id])==P.serialize(c),"crop changed Hat identity or boundary")
    shared=shared+1
  end
end
check(shared>10,"overlap lacks common hats")
local common={7,4.3,8.9,6.5}
local pa,pb=export("common-a",a,common),export("common-b",b,common)
check(V.pdf(pa)==V.pdf(pb) and V.svg(pa)==V.svg(pb),"equal physical crops disagree")
local corrupt=P.plain(whole)
corrupt.structures.tiling.cells[1].kites[1][1][1]=corrupt.structures.tiling.cells[1].kites[1][1][1]+1
check(not pcall(F.validate,corrupt),"forged kite accepted")
check(whole.extensions.hat.certificate.reflected==22 and #whole.extensions.hat.hierarchy>10,
  "reflected leaves or metatile ancestry missing")

local env=Q.environment({revision="working/hat/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},
  {id=V.VERSION,version="1"})
local good={width=5,height=4,holes={{3,2}},boundary={{cell={1,1},side="west",mark=1},{cell={5,4},side="east",mark=1}}}
local impossible={width=2,height=2,boundary={{cell={1,1},side="west",mark=1}}}
local solver_box={-.25,-.25,3,2.45}
local function make_recipe(name,problem,parameters,assignment)
  parameters.cell_size=.55
  local spec=P.specification({id="fixture/"..name,definition_ref={id=solver.id,version=solver.version},seed=18,
    parameters=parameters,inputs={problem=problem,assignment=assignment},constraints={},style={},budget=limits,
    document={unit="cm",bounds=solver_box,protected_regions=P.array()}},solver)
  return Q.from_specification(solver,spec,{unit="cm",transform={1,0,0,1,0,0},crop=solver_box,
    protected_regions=P.array(),derived=false,validity="construction_preserved"},2)
end
local function execute(recipe) return Q.execute(Q.decode(Q.encode(recipe)),reg,env) end
local saved=make_recipe("solved",good,{})
local solved=execute(saved)
assert(solved.record.status=="complete",P.serialize(solved.record.diagnostics))
local witness=solved.instance.extensions.constraint.assignment
local replay=execute(make_recipe("witness",good,{node_limit=0},P.plain(witness)))
check(replay.record.status=="complete" and replay.record.extensions.solver.route=="replayed"
  and replay.record.extensions.solver.nodes==0,"solver-free replay failed")
check(solved.instance.id==replay.instance.id and solved.bytes.scene==replay.bytes.scene,
  "replay altered the geometric solution")
local failures={
  unsatisfiable=make_recipe("impossible",impossible,{}),
  unknown=make_recipe("exhausted",good,{node_limit=0}),
  timeout=make_recipe("deadline",good,{deadline_ms=2}),
}
for _,wanted in ipairs{"unsatisfiable","unknown","timeout"} do
  local bad=failures[wanted]
  local out=execute(bad)
  check(out.record.status=="failed" and #out.record.outputs==0 and out.record.extensions.solver.status==wanted,
    "incorrect solver failure status: "..wanted)
  write(wanted..".recipe",Q.encode(bad))
  write_build(wanted,out.record)
end
local wrong=P.plain(witness)
wrong[1].tile="blank"
local rejected=execute(make_recipe("corrupt",good,{},wrong))
check(rejected.record.status=="failed" and #rejected.record.outputs==0,"forged witness accepted")
local q=V.plan(solved.scene,solved.instance,solved.view,solver)
write("completion.pdf",V.pdf(q));write("completion.svg",V.svg(q))
write("completion.instance",solved.bytes.instance)
write("completion.recipe",Q.encode(saved))
write("replay.recipe",Q.encode(make_recipe("witness",good,{node_limit=0},P.plain(witness))))
write_build("completion",solved.record)
write_build("replay",replay.record)
A.write(root.."/receipt.json",P.serialize({stage="18",source_digest=digest,checks=checks,outputs=output,shared=shared}))
print("Hat and finite constraints: "..checks.." checks; "..shared.." shared hats")
