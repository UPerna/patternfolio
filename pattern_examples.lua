-- Small running contract examples, not implementations of future families.
local P,R=require("pattern"),require("pattern_registry")
local M={}
local function definition(id,family,capabilities,metric,parameters)
  return P.definition({id=id,version=(id=="example/graph" and "1" or "2"),family=family,capabilities=capabilities,
    parameters=parameters or {},units="cm",transforms={metric_constrained=metric,reflection=not metric,uniform_scale=true},
    assumptions={"Contract fixture only; source-family implementation gates remain pending"}})
end
function M.definitions()
  return {
    floral=definition("example/floral","existing-floral-primitive",{"growth"},false,{size={type="number",minimum=0.1,maximum=2,required=true}}),
    graph=definition("example/graph","graph-contract-fixture",{"graph"},false),
    tiling=definition("example/tiling","two-square-contract-fixture",{"tiling"},true),
  }
end
function M.specification(d)
  return P.specification({id=d.id.."/spec",definition_ref={id=d.id,version=d.version},parameters=d.family=="existing-floral-primitive" and {size=0.8} or {},
    inputs={},constraints={},style={},seed=7,document={unit="cm",bounds={0,0,8,8},protected_regions=P.array()}},d)
end
local function instance(d,structures,extra)
  return {id=d.id.."/instance",definition_ref={id=d.id,version=d.version},
    frame={id="example/world",dimension=2,unit="cm",handedness="right",origin={0,0}},structures=structures,
    provenance={generator=d.id,generator_version=d.version,seed=7,construction="explicit canonical contract fixture"},extensions=extra or {}}
end
function M.view(x,definition,crop)
  return P.view({id=x.id.."/view",instance_ref=x.id,unit="cm",transform={1,0,0,1,0,0},
    crop=crop or {0,0,8,8},protected_regions=P.array(),derived=false,validity="construction_preserved"},x,definition)
end
local function scene(x,v,operations,resources)
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=operations,resources=resources or P.array()}
end
local function point(v,p)
  local m=v.transform;return m[1]*p[1]+m[3]*p[2]+m[5],m[2]*p[1]+m[4]*p[2]+m[6]
end
local function style_keys(style,allowed)
  for k in pairs(style) do assert(allowed[k],"unsupported example style control: "..k) end
end
local function native_flower(seed,size) return require("pattern_ink").flower(seed,size) end
function M.registry()
  local registry=R.new();local defs=M.definitions()
  registry:register(defs.floral,{
    generate=function(s,c)
      c:consume("objects",1)
      return instance(defs.floral,{growth={nodes={{id="floral/root",point={3,3},motif="flower",parameters={size=s.parameters.size}}},roots={"floral/root"}}},
        {resource=native_flower(s.seed,s.parameters.size),interop={pdf=true,svg=true,neutral=true}})
    end,
    validate=function(x) return {ok=#x.structures.growth.nodes==1 and #x.extensions.resource.variants.scene.content>1000,checks={"actual existing floral primitive emitted paths and graphics resources"}} end,
    lower=function(x,v,s)
      style_keys(s,{})
      local m=v.transform
      return scene(x,v,{{op="symbol",semantic_ref="floral/root",resource_ref=x.extensions.resource.id,
        transform={m[1],m[2],m[3],m[4],m[5],m[6]}}},{P.plain(x.extensions.resource)})
    end,
  })
  registry:register(defs.graph,{
    generate=function(s,c)
      c:consume("objects",5)
      return instance(defs.graph,{graph={vertices={{id="graph/a",point={0,0}},{id="graph/b",point={1,1}},{id="graph/c",point={2,0}}},
        edges={{id="graph/ab",from="graph/a",to="graph/b"},{id="graph/bc",from="graph/b",to="graph/c"}}}})
    end,
    validate=function(x)
      local g=x.structures.graph
      return {ok=#g.vertices==3 and #g.edges==2 and g.vertices[2].point[2]==1,checks={"canonical three-vertex two-edge analytic fixture"}}
    end,
    lower=function(x,v,s)
      style_keys(s,{stroke=true,stroke_width=true})
      local vertices,ops={},{}
      for _,p in ipairs(x.structures.graph.vertices) do vertices[p.id]=p.point end
      for _,e in ipairs(x.structures.graph.edges) do
        local ax,ay=point(v,vertices[e.from]);local bx,by=point(v,vertices[e.to])
        ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",ax,ay},{"L",bx,by}},paint={stroke=s.stroke or {0.1,0.2,0.4},stroke_width=s.stroke_width or 0.03}}
      end
      return scene(x,v,ops)
    end,
  })
  registry:register(defs.tiling,{
    generate=function(s,c)
      c:consume("objects",15)
      local vertices={{id="tile/00",point={0,0}},{id="tile/10",point={1,0}},{id="tile/20",point={2,0}},
        {id="tile/01",point={0,1}},{id="tile/11",point={1,1}},{id="tile/21",point={2,1}}}
      local function e(id,a,b,owner,role) return {id=id,from=a,to=b,owner=owner,role=role or "patch_boundary"} end
      local edges={e("tile/e0","tile/00","tile/10","tile/A"),e("tile/shared","tile/10","tile/11","tile/A","interior"),
        e("tile/e2","tile/11","tile/01","tile/A"),e("tile/e3","tile/01","tile/00","tile/A"),
        e("tile/e4","tile/10","tile/20","tile/B"),e("tile/e5","tile/20","tile/21","tile/B"),e("tile/e6","tile/21","tile/11","tile/B")}
      local function b(id,reversed) return {edge=id,reversed=not not reversed} end
      local cells={{id="tile/A",prototype="unit-square",chirality=1,boundary={b("tile/e0"),b("tile/shared"),b("tile/e2"),b("tile/e3")}},
        {id="tile/B",prototype="unit-square",chirality=1,boundary={b("tile/e4"),b("tile/e5"),b("tile/e6"),b("tile/shared",true)}}}
      return instance(defs.tiling,{tiling={vertices=vertices,edges=edges,cells=cells,hierarchy={{id="tile/patch",children={"tile/A","tile/B"}}}}})
    end,
    validate=function(x)
      local t=x.structures.tiling;local vs,es={},{}
      for _,v in ipairs(t.vertices) do vs[v.id]=v.point end;for _,e in ipairs(t.edges) do es[e.id]=e end
      local area=0
      for _,cell in ipairs(t.cells) do
        local first,last;local sum=0
        for _,b in ipairs(cell.boundary) do
          local e=es[b.edge];local a=vs[b.reversed and e.to or e.from];local z=vs[b.reversed and e.from or e.to]
          if last then assert(last==a,"cell boundary does not close through shared vertices") end
          first=first or a;last=z;sum=sum+a[1]*z[2]-z[1]*a[2]
        end
        assert(last==first and math.abs(sum/2-1)<1e-12,"canonical unit-square area/closure failure");area=area+sum/2
      end
      return {ok=area==2,checks={"independent directed boundary closure and analytical unit-square area"}}
    end,
    lower=function(x,v,s)
      style_keys(s,{fill=true,stroke=true,stroke_width=true})
      local t=x.structures.tiling;local vs,es,ops={},{},{}
      for _,p in ipairs(t.vertices) do vs[p.id]=p.point end;for _,e in ipairs(t.edges) do es[e.id]=e end
      for _,cell in ipairs(t.cells) do
        local commands={}
        for i,b in ipairs(cell.boundary) do
          local e=es[b.edge];local a=vs[b.reversed and e.to or e.from];local z=vs[b.reversed and e.from or e.to]
          if i==1 then local px,py=point(v,a);commands[#commands+1]={"M",px,py} end
          local px,py=point(v,z);commands[#commands+1]={"L",px,py}
        end
        commands[#commands+1]={"Z"}
        ops[#ops+1]={op="path",semantic_ref=cell.id,commands=commands,paint={fill=s.fill or {0.3,0.5,0.8}}}
      end
      -- Stroke each globally owned edge once after painting the cells.
      for _,e in ipairs(t.edges)do
        local ax,ay=point(v,vs[e.from]);local bx,by=point(v,vs[e.to])
        ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",ax,ay},{"L",bx,by}},paint={stroke=s.stroke or {0.1,0.1,0.1},stroke_width=s.stroke_width or 0.02}}
      end
      return scene(x,v,ops)
    end,
  })
  return registry,defs
end
return M
