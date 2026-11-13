-- Bounded analytic unit-square fixture for document-view tests. This is not
-- the periodic/wallpaper family implementation reserved for stage09.
local P,G,T=require("pattern"),require("pattern_geometry"),require("pattern_topology")
local M={}
function M.register(registry)
  local d=P.definition({id="fixture/planner-grid",version="1",family="analytic-view-fixture",capabilities={"tiling"},units="cm",
    parameters={width={type="integer",minimum=2,maximum=20,required=true},height={type="integer",minimum=2,maximum=20,required=true}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},assumptions={"Explicit bounded unit-square analytic fixture; no wallpaper registry or source-family completion claim"}})
  local calls=0
  registry:register(d,{
    generate=function(s,c)
      calls=calls+1;local w,h=s.parameters.width,s.parameters.height;local vertices,edges,cells,children={},{},{},{}
      local function v(i,j)return "v/"..i.."/"..j end;local function cell(i,j)return "cell/"..i.."/"..j end
      local function horizontal(i,j)return "h/"..i.."/"..j end;local function vertical(i,j)return "e/"..i.."/"..j end
      for j=0,h do for i=0,w do vertices[#vertices+1]={id=v(i,j),point={i,j}}end end
      for j=0,h do for i=0,w-1 do edges[#edges+1]={id=horizontal(i,j),from=v(i,j),to=v(i+1,j),owner=cell(i,j>0 and j-1 or 0),role=j>0 and j<h and "interior" or "patch_boundary"}end end
      for j=0,h-1 do for i=0,w do edges[#edges+1]={id=vertical(i,j),from=v(i,j),to=v(i,j+1),owner=cell(i>0 and i-1 or 0,j),role=i>0 and i<w and "interior" or "patch_boundary"}end end
      local function use(id,reverse)return {edge=id,reversed=reverse or false}end
      for j=0,h-1 do for i=0,w-1 do local id=cell(i,j);children[#children+1]=id;cells[#cells+1]={id=id,prototype=(i+j)%2==0 and "unit-square/even" or "unit-square/odd",chirality=1,
        boundary={use(horizontal(i,j)),use(vertical(i+1,j)),use(horizontal(i,j+1),true),use(vertical(i,j),true)}}end end
      c:consume("objects",#vertices+#edges+#cells)
      return {id=d.id.."/instance/"..w.."/"..h,definition_ref={id=d.id,version=d.version},frame={id="planner/world",dimension=2,unit="cm",handedness="right",origin={0,0}},
        structures={tiling={vertices=vertices,edges=edges,cells=cells,hierarchy={{id="patch",children=children}}}},
        provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction="bounded analytic unit squares at integer world addresses"},extensions={}}
    end,
    validate=function(x,c)
      local result=T.inspect(x,d,G.policy("cm",20));c:consume("operations",result.pair_checks)
      return {ok=result.ok,checks={"independent semantic edge incidence, closure, positive areas, duplicates and crossings"}}
    end,
    lower=function(x,v,s)
      for k in pairs(s)do assert(k=="stroke_width" or k=="stroke" or k=="fill","unsupported analytic-grid style")end
      local t=x.structures.tiling;local vs,es,ops={},{},{}
      for _,p in ipairs(t.vertices)do vs[p.id]=p.point end;for _,e in ipairs(t.edges)do es[e.id]=e end
      for _,cell in ipairs(t.cells)do
        local commands={}
        for i,u in ipairs(cell.boundary)do local e=es[u.edge];local a=G.transform(vs[u.reversed and e.to or e.from],v.transform);local b=G.transform(vs[u.reversed and e.from or e.to],v.transform)
          if i==1 then commands[#commands+1]={"M",a[1],a[2]}end;commands[#commands+1]={"L",b[1],b[2]}
        end
        commands[#commands+1]={"Z"};ops[#ops+1]={op="path",semantic_ref=cell.id,commands=commands,paint={fill=s.fill or (cell.prototype=="unit-square/even" and {0.2,0.5,0.8} or {0.75,0.65,0.3})}}
      end
      for _,e in ipairs(t.edges)do local a,b=G.transform(vs[e.from],v.transform),G.transform(vs[e.to],v.transform)
        ops[#ops+1]={op="path",semantic_ref=e.id,commands={{"M",a[1],a[2]},{"L",b[1],b[2]}},paint={stroke=s.stroke or {0.1,0.1,0.1},stroke_width=s.stroke_width or 0.025}}
      end
      return {id=x.id.."/scene/"..v.id,instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
    end,
  })
  return d,function()return calls end
end
return M
