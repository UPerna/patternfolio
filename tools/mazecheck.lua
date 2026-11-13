local P,R,Q,E=require("pattern"),require("pattern_registry"),require("pattern_recipe"),require("pattern_examples")
local M,C,V,H,A=require("pattern_maze"),require("pattern_maze_chart"),require("pattern_render"),require("pattern_hash"),require("pattern_artifact")
local fs=require("lfs")
local source,hashes={},{}
local function read(name)
  local f=assert(io.open(name,"rb"));local bytes=f:read("*a"):gsub("\r\n","\n");f:close()
  source[name],hashes[name]=bytes,H.sha256(bytes)
end
for name in fs.dir(".") do if name:match("%.lua$") then read(name) end end
read("tools/mazecheck.lua");read("tools/maze_oracle.py")
local digest=H.value("maze/source",hashes)
local folder="build/maze/"..digest
for _,p in ipairs{"build","build/maze",folder} do fs.mkdir(p) end
local outputs={}
local function write(name,bytes) outputs[name]=A.write(folder.."/"..name,bytes) end
local reg=R.new()
local d=M.register(reg)
local env=Q.environment({revision="working/maze/"..digest,files={construction=source,style={},view={},renderer={}}},
  {lua=_VERSION,host=PATTERN_TEST_HOST or "texlua/"..tostring(status and status.luatex_version)},{id=V.VERSION,version="1"})
local checks=0
local function check(ok,msg) assert(ok,msg);checks=checks+1 end
local b={0,0,10,7}
local page={-.28,-.28,10.28,7.28}
local limits={objects=85000,operations=18000000,bytes=64*1024*1024}
local function recipe(name,params,input,view)
  return Q.from_specification(d,{id="maze/"..name,definition_ref={id=d.id,version=d.version},seed=23,
    parameters=params,inputs=input or {},style={},constraints={},budget=limits,
    document={unit="cm",bounds=b,protected_regions=P.array()}},
    {unit="cm",transform={1,0,0,1,0,0},crop=view or page,protected_regions=P.array(),derived=false,
      validity="construction_preserved"},2)
end
local function run(q)
  return Q.execute(Q.decode(Q.encode(q)),reg,env)
end
local function render(name,x,crop,display)
  local context=R.context({seed=23,frame=P.plain(x.frame),source={revision="working/maze/"..digest},limits=limits})
  local v=E.view(x,d,crop)
  local scene=reg:lower(d.id,x,v,{display=display},context)
  local plan=V.plan(scene,x,v,d)
  write(name..".pdf",V.pdf(plan));write(name..".svg",V.svg(plan))
end
local function build(name,params,input,solution)
  local q=recipe(name,params,input)
  local r=run(q)
  assert(r.record.status=="complete",name..": "..P.serialize(r.record.diagnostics))
  local x=r.instance
  local m=x.extensions.maze
  check(m.solution.passages==#m.cells-1 and #m.solution.route>4,name.." route")
  check(P.serialize(run(q).instance)==P.serialize(x),name.." replay")
  write(name..".recipe",Q.encode(q));write(name..".instance",P.serialize(x))
  render(name,x,page,"walls")
  if solution then render(name.."-solution",x,page,"solution") end
  print(name,#m.cells,#m.solution.route,#m.solution.guide)
  return x
end
local guided={profile="directional",image="ramp",columns=22,rows=15,bias=.64}
local main=build("directional",guided,nil,true)
local unguided=P.plain(guided)
unguided.guided=false
local base=build("unguided",unguided)
local function preferred(x)
  local n=0
  for _,w in ipairs(x.extensions.maze.walls) do if w.open and w.bias=="preferred-removal" then n=n+1 end end
  return n
end
check(preferred(main)>preferred(base)+35,"routing bias did not alter passage directions")
local ribbon=build("ribbon",{profile="directional",image="ribbon",columns=23,rows=14,bias=.68})
local foreshort=build("perspective",{profile="directional",image="ramp",columns=20,rows=14,perspective=.43})
local spiral=build("spiral",{profile="spiral",image="radial",columns=22,rows=6,bias=.63,min_wall=.01,min_passage=.023})
local vortex=build("vortex",{profile="vortex",image="radial",columns=22,rows=6,bias=.66,min_wall=.01,min_passage=.023})
local random=build("random",{profile="random",image="constant",columns=19,rows=14,relax=8})
local path=build("guided",guided,{guide={{1.6,3.3},{4.9,4.8},{7.1,2.4},{8.1,4.9}}},true)
local holed=build("holed",{profile="holed",image="constant",columns=20,rows=15,notch=true},
  {holes={{.43,.42,.13},{.73,.67,.10}}},true)
local tiling=build("aperiodic",{profile="aperiodic",image="constant",edge_length=.62},nil,true)
check(#path.extensions.maze.solution.guide>=20,"guide was not pinned")
check(#holed.extensions.maze.chart.removed>15,"holed fixture did not remove cells")
check(tiling.extensions.maze.chart.source_cells>#tiling.extensions.maze.cells,"full-cell P3 selection missing")
check(random.extensions.maze.chart.relaxations==8 and spiral.extensions.maze.chart.angular_sectors==22
  and vortex.extensions.maze.chart.angular_sectors==22,"missing texture construction provenance")
render("crop",main,{2.4,1.5,6.5,5.6},"walls")
check(main.extensions.maze.guarantee=="unique full-maze route; crop is display only","crop policy")
local s,w,g=C.tone(0,.013,.035,.48)
check(math.abs(s-w-.035)<1e-12 and math.abs((s-w)/s-g)<1e-12,"dark tone relation")
s,w,g=C.tone(1,.013,.035,.48)
check(w==.013 and math.abs((s-w)/s-g)<1e-12,"light tone relation")
local repeated=run(recipe("bad-guide",guided,{guide={{4,4},{4,4}}}))
check(repeated.record.status~="complete","repeated route cell accepted")
local disconnected=run(recipe("disconnected",{profile="holed",columns=20,rows=15},{holes={{.5,.26,.29},{.5,.74,.29}}}))
check(disconnected.record.status~="complete","disconnected maze accepted")
local narrow=run(recipe("too-tight",{profile="directional",columns=40,rows=16,min_wall=.08,min_passage=.14}))
check(narrow.record.status~="complete","unprintable profile accepted")
write("failures.json",P.serialize({repeated=P.plain(repeated.record.diagnostics),
  disconnected=P.plain(disconnected.record.diagnostics),too_tight=P.plain(narrow.record.diagnostics)}))
A.write(folder.."/receipt.json",P.serialize({stage="23",source_digest=digest,checks=checks,outputs=outputs,
  preferred={guided=preferred(main),baseline=preferred(base)}}))
print("Maze checks passed",checks,digest)

