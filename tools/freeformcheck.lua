local P,R,E,Q=require("pattern"),require("pattern_registry"),require("pattern_examples"),require("pattern_recipe")
local C,F=require("pattern_circle_packing"),require("pattern_freeform")
local A,H,V=require("pattern_artifact"),require("pattern_hash"),require("pattern_render")
local fs=require("lfs")
local names={"tools/freeformcheck.lua","tools/freeform_oracle.py"}
for n in fs.dir(".") do if n:match("%.lua$") then names[#names+1]=n end end
table.sort(names,P.byte_less)
local source,bytes={},{}
for _,n in ipairs(names) do
  local f=assert(io.open(n,"rb"))
  bytes[n]=f:read("*a"):gsub("\r\n","\n");f:close()
  source[#source+1]={path=n,sha256=H.sha256(bytes[n])}
end
local digest=H.sha256(P.serialize(source))
local root="build/freeform/"..digest
for _,d in ipairs{"build","build/freeform",root} do fs.mkdir(d) end
local outputs={}
local function write(n,data) outputs[n]=A.write(root.."/"..n,data) end
local registry=R.new()
local definition=F.register(registry)
local frame={id=definition.id.."/global",dimension=2,unit="cm",handedness="right",origin={0,0}}
local limits={objects=25000,operations=400000,bytes=32*1024*1024}
local crop={0,0,6,6}
local host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version or "unreported")
local environment=Q.environment({revision="working/freeform/"..digest,
  files={construction=bytes,style={},view={},renderer={}}},{lua=_VERSION,host=host},{id=V.VERSION,version="1"})
local function context()
  return R.context({seed=12,frame=frame,limits=limits,source={revision="working/freeform/"..digest}})
end
local function disk(edit)
  local faces={}
  for i=1,6 do
    local a,b="b"..i,"b"..(i%6+1)
    if edit and i==1 then
      faces[#faces+1]={"center",a,"inner"}
      faces[#faces+1]={a,b,"inner"}
      faces[#faces+1]={b,"center","inner"}
    else faces[#faces+1]={"center",a,b} end
  end
  return {faces=faces}
end
local function spec(name,inputs,parameters)
  return P.specification({id="fixture/"..name,definition_ref={id=definition.id,version=definition.version},
    seed=12,parameters=parameters,inputs=inputs,constraints={},style={stroke_width=.026},budget=limits,
    document={unit="cm",bounds=crop,protected_regions=P.array()}},definition)
end
local function build(s)
  return registry:generate(definition.id,s,context())
end
local function render(n,x)
  local view=E.view(x,definition,crop)
  local scene=registry:lower(definition.id,x,view,{stroke_width=.026},context())
  local plan=V.plan(scene,x,view,definition)
  write(n..".pdf",V.pdf(plan));write(n..".svg",V.svg(plan))
  return view,scene
end
local checks=0
local function check(v,why) assert(v,why);checks=checks+1 end
local summaries={}
local edit=disk(true)
local cases={{"base",disk(false),{.3,.3,5.7,5.7}},{"mixed",edit,{.3,.3,5.7,5.7}},
  {"panel",edit,{.9,.62,5.1,5.38}}}
local records={}
for _,row in ipairs(cases) do
  local name,complex,panel=table.unpack(row)
  local s=spec(name,{complex=complex,panel=panel},{tolerance=1e-11})
  local r,e=build(s)
  assert(r,e and P.serialize(e))
  local x=r.instance
  local k=x.extensions.freeform
  local view,scene=render(name,x)
  write(name..".instance",P.serialize(x))
  local actual={}
  for _,v in pairs(k.wheels) do actual[#actual+1]=v.order end
  table.sort(actual)
  check(P.serialize(actual)==(name=="base" and "[12]" or "[6,14]"),"unexpected wheel orders")
  check(#scene.operations>0,"empty ornament")
  summaries[name]={orders=actual,faces=#k.patch.faces,contacts=#k.contacts,links=#x.structures.graph.edges}
  if name=="panel" then
    local saved=spec(name,{packing=P.plain(k.packing)},{})
    local recipe=Q.encode(Q.from_specification(definition,saved,view,2))
    local original_solver=C.solve
    C.solve=function() error("replay unexpectedly called the solver") end
    local replay=Q.execute(Q.decode(recipe),registry,environment)
    local again=Q.execute(Q.decode(recipe),registry,environment)
    C.solve=original_solver
    check(replay.record.status=="complete",P.serialize(replay.record))
    check(P.serialize(replay.instance.structures.graph)==P.serialize(x.structures.graph),"replay changed graph")
    check(replay.bytes.instance==again.bytes.instance and replay.bytes.scene==again.bytes.scene,"replay not deterministic")
    check(replay.record.extensions.solver.route=="replayed","missing solver receipt")
    check(replay.record.extensions.solver.maximum_tangency_residual==k.packing.maximum_tangency_residual,
      "solver residual missing from Build record")
    write("panel.recipe",recipe);write("panel-replay.instance",replay.bytes.instance);write("panel-replay.scene",replay.bytes.scene)
    records.panel=P.plain(replay.record)
    local stalled=spec("stalled",{complex=edit},{max_iterations=1})
    local failure=Q.execute(Q.from_specification(definition,stalled,view,2),registry,environment)
    check(failure.record.status=="failed" and P.serialize(failure.record.diagnostics):find("packing-nonconvergence",1,true),
      "nonconvergence missing from Build record")
    records.stalled=P.plain(failure.record)
    local tampered=P.plain(k.packing)
    tampered.circles.inner.center[1]=tampered.circles.inner.center[1]+.1
    local broken,diagnostic=build(spec("tampered",{packing=tampered},{}))
    check(not broken and P.serialize(diagnostic):find("packing-tangency-residual",1,true),"corrupt packing accepted")
  end
end
local sensitivity={}
for _,tol in ipairs{1e-8,1e-11,1e-13} do
  local p=C.solve(edit,{tolerance=tol,panel={.3,.3,5.7,5.7}})
  check(C.validate(p),"invalid tolerance witness")
  sensitivity[#sensitivity+1]=p
end
check(sensitivity[1].maximum_tangency_residual>sensitivity[3].maximum_tangency_residual,"tolerance had no measured effect")
write("tolerances.json",P.serialize(sensitivity))
local function rejects(s,code)
  local r,e=build(s)
  check(not r and P.serialize(e):find(code,1,true),"missing diagnostic "..code)
end
local reversed=disk(true)
reversed.faces[1][1],reversed.faces[1][2]=reversed.faces[1][2],reversed.faces[1][1]
rejects(spec("bad-orientation",{complex=reversed},{}),"packing-edge-incidence-or-orientation")
rejects(spec("stalled",{complex=edit},{max_iterations=1}),"packing-nonconvergence")
rejects(spec("unmatched",{complex=edit},{contact_angle=55}),"pic-unmatched-ray")
local report={stage="12",source_digest=digest,source=source,checks=checks,fixtures=summaries,outputs=outputs,
  runtime=_VERSION,host=host,build_records=records}
A.write(root.."/receipt-".._VERSION:gsub(" ","-")..".json",P.serialize(report).."\n")
print("freeformcheck: "..checks.." checks; source "..digest)
