-- Connectivity and geometric integrity are read from semantic objects, not paths.
local P,G,E,N=require("pattern"),require("pattern_geometry"),require("pattern_exact"),require("pattern_predicates")
local T={VERSION="semantic-topology-v1"}
local function sorted_keys(map) local out=P.array();for k in pairs(map) do out[#out+1]=k end;table.sort(out,P.byte_less);return out end
local function pair_key(a,b) if P.byte_less(b,a) then a,b=b,a end;return P.serialize({a,b}) end
function T.inspect(instance,definition,policy,options)
  options=options or {};local report={ok=false,errors=P.array(),observations=P.array(),checks=P.array(),adjacency={},components={},cells={},owners=P.array(),pair_checks=0}
  local function error_message(message) report.errors[#report.errors+1]=message end
  local ok,problem=pcall(function()
    local allowed={allow_crossings=true,allow_multiedges=true,allow_coincident_vertices=true,max_pair_checks=true}
    for k,v in pairs(options) do assert(allowed[k],"unknown topology option "..tostring(k));if k~="max_pair_checks" then assert(type(v)=="boolean","topology policy flags must be boolean") end end
    local x=P.instance(P.plain(instance),definition);G.tolerance(policy)
    report.checks[#report.checks+1]="schema integrity for declared capabilities"
    assert(x.frame.unit==policy.unit,"topology check unit mismatch")
    local limit=options.max_pair_checks or 100000
    assert(type(limit)=="number" and limit%1==0 and limit>=0,"invalid topology pair budget")
    local function charge() report.pair_checks=report.pair_checks+1;assert(report.pair_checks<=limit,"topology pair-check budget exhausted") end
    local function inspect_complex(s,tiling)
      assert(x.frame.dimension==2,"planar geometry checks require a 2D instance; 3D connectivity remains separate")
      local vertices,edges={},{};local coordinate_mode
      for _,v in ipairs(s.vertices) do
        vertices[v.id]=v;report.adjacency[v.id]=P.array()
        local mode=v.exact and "exact" or "binary64";coordinate_mode=coordinate_mode or mode
        assert(mode==coordinate_mode,"mixed construction coordinates require an explicit validated conversion")
      end
      local function same_vertex(a,b)
        if a.exact then return E.compare(a.exact.components[1],b.exact.components[1])==0 and E.compare(a.exact.components[2],b.exact.components[2])==0 end
        return a.point[1]==b.point[1] and a.point[2]==b.point[2]
      end
      for i,a in ipairs(s.vertices) do for j=i+1,#s.vertices do
        charge();local b=s.vertices[j]
        if same_vertex(a,b) then
          local message="coincident distinct vertex identities: "..a.id..", "..b.id
          if options.allow_coincident_vertices and not tiling then report.observations[#report.observations+1]=message else error_message(message) end
        end
      end end
      local pairs_seen={}
      for _,e in ipairs(s.edges) do
        edges[e.id]=e;report.adjacency[e.from][#report.adjacency[e.from]+1]=e.id;report.adjacency[e.to][#report.adjacency[e.to]+1]=e.id
        local key=pair_key(e.from,e.to)
        if pairs_seen[key] then
          local message="duplicate endpoint-pair edges: "..pairs_seen[key]..", "..e.id
          if options.allow_multiedges and not tiling then report.observations[#report.observations+1]=message else error_message(message) end
        else pairs_seen[key]=e.id end
      end
      for _,neighbors in pairs(report.adjacency) do table.sort(neighbors,P.byte_less) end
      for i,a in ipairs(s.edges) do for j=i+1,#s.edges do
        charge();local b=s.edges[j];local hit
        if coordinate_mode=="exact" then hit=G.intersect_exact_segments(vertices[a.from].exact,vertices[a.to].exact,vertices[b.from].exact,vertices[b.to].exact)
        else hit=G.segment_intersection(vertices[a.from].point,vertices[a.to].point,vertices[b.from].point,vertices[b.to].point,policy) end
        local shared=a.from==b.from or a.from==b.to or a.to==b.from or a.to==b.to
        local expected=hit.kind=="none" or hit.kind=="point" and hit.classification=="endpoint" and shared
        if not expected then
          local message="edge geometry "..hit.kind..": "..a.id..", "..b.id
          local allowed=not tiling and ((options.allow_crossings and hit.kind=="point") or (options.allow_multiedges and hit.kind=="overlap" and pair_key(a.from,a.to)==pair_key(b.from,b.to)))
          if allowed then report.observations[#report.observations+1]=message else error_message(message) end
        end
      end end
      -- Components are deterministic even when a geometric check failed.
      local seen,components={},P.array()
      for _,id in ipairs(sorted_keys(vertices)) do if not seen[id] then
        local stack={id};local component=P.array();seen[id]=true
        while #stack>0 do local v=table.remove(stack);component[#component+1]=v
          for _,eid in ipairs(report.adjacency[v]) do local e=edges[eid];local other=e.from==v and e.to or e.from;if not seen[other] then seen[other]=true;stack[#stack+1]=other end end
        end
        table.sort(component,P.byte_less);components[#components+1]=component
      end end
      report.components[tiling and "tiling" or "graph"]=components
      report.checks[#report.checks+1]=(tiling and "tiling" or "graph").." connectivity, duplicate geometry and planar edge intersections"
      if tiling then
        local incidence={};local neighbors={}
        for _,cell in ipairs(s.cells) do
          neighbors[cell.id]={};local ordered=P.array();local previous,first
          for _,use in ipairs(cell.boundary) do
            local e=edges[use.edge];local from,to=e.from,e.to;if use.reversed then from,to=to,from end
            if previous and previous~=from then error_message("cell boundary is not a connected walk: "..cell.id) end
            first=first or from;previous=to;ordered[#ordered+1]=from
            incidence[e.id]=incidence[e.id] or {};incidence[e.id][#incidence[e.id]+1]=cell.id
          end
          if previous~=first or #ordered<3 then error_message("cell boundary is not a closed polygon: "..cell.id) end
          local area,rounding=0,0
          if #ordered>=3 then
            if coordinate_mode=="exact" then
              local sum=E.new(0)
              for i,id in ipairs(ordered) do local a,b=vertices[id].exact.components,vertices[ordered[i%#ordered+1]].exact.components;sum=E.add(sum,E.sub(E.mul(a[1],b[2]),E.mul(a[2],b[1]))) end
              report.cells[cell.id]={vertices=ordered,signed_double_area_exact=sum}
              if E.compare(sum,E.new(0))<=0 then error_message("cell has zero/negative exact area: "..cell.id) end
            else
              local origin=vertices[ordered[1]].point;local magnitude=0
              for i=2,#ordered-1 do local value,err=N.determinant_value(origin,vertices[ordered[i]].point,vertices[ordered[i+1]].point);area=area+value;magnitude=magnitude+math.abs(value);rounding=rounding+err end
              rounding=rounding+16*2^-52*magnitude
              report.cells[cell.id]={vertices=ordered,signed_double_area=area,area_rounding_bound=rounding}
              if area<=rounding then error_message("cell area is zero, negative or unresolved within rounding: "..cell.id) end
            end
          end
        end
        for _,e in ipairs(s.edges) do
          local uses=incidence[e.id] or {};report.owners[#report.owners+1]={edge=e.id,owner=e.owner,role=e.role,incident_cells=uses}
          if #uses==2 then neighbors[uses[1]][uses[2]]=true;neighbors[uses[2]][uses[1]]=true end
        end
        report.cell_adjacency={};for id,map in pairs(neighbors) do report.cell_adjacency[id]=sorted_keys(map) end
      end
    end
    if x.structures.graph then inspect_complex(x.structures.graph,false) end
    if x.structures.tiling then inspect_complex(x.structures.tiling,true) end
    if x.structures.strands then report.strands={components=#x.structures.strands.components,crossings=#x.structures.strands.crossings,ports=#x.structures.strands.ports} end
    if x.structures.curve3d then report.curves3d={vertices=#x.structures.curve3d.vertices,curves=#x.structures.curve3d.curves,validation="connectivity_only_no_3d_intersection_claim"} end
  end)
  if not ok then error_message(tostring(problem)) end
  report.ok=#report.errors==0;return P.snapshot(report)
end
function T.strand(instance,id)
  local s=assert(instance.structures.strands,"instance has no strand semantics")
  for _,v in ipairs(s.components) do if v.id==id then return P.snapshot({id=id,closed=v.closed,alternating=v.alternating,endpoints=P.plain(v.endpoints),encounters=P.plain(v.encounters)}) end end
  error("unknown strand component "..tostring(id),0)
end
function T.ancestors(instance,id)
  local parents,known={},{}
  local growth=instance.structures.growth
  if growth then for _,v in ipairs(growth.nodes) do known[v.id]=true;parents[v.id]=v.parent end end
  local tiling=instance.structures.tiling
  if tiling then
    for _,v in ipairs(tiling.cells) do known[v.id]=true end
    for _,v in ipairs(tiling.hierarchy or {}) do known[v.id]=true;for _,child in ipairs(v.children) do assert(not parents[child],"multiple construction parents");parents[child]=v.id end end
  end
  assert(known[id],"unknown construction identity");local out=P.array();local seen={[id]=true};local p=parents[id]
  while p do assert(not seen[p],"cyclic construction ancestry");seen[p]=true;out[#out+1]=p;p=parents[p] end
  return P.snapshot(out)
end
return T
