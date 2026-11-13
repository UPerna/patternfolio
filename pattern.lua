-- Versioned data contracts. Generators retain their own semantic structures.
-- Geometry algorithms, canonical recipes and renderers are separate stages.
local json = require("pattern_json")
local M = { VERSION = 1, TOLERANCE = 1e-9 }
local stored = setmetatable({}, {__mode="k"})
local function fail(path, message) error("pattern: "..path..": "..message, 0) end
local function need(ok, path, message) if not ok then fail(path,message) end end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function id(v,p) need(type(v)=="string" and #v>0 and #v<=256,p,"expected a nonempty stable ID") end
local function seq(t,p)
  need(type(t)=="table",p,"expected an array")
  local data=stored[t] or t;local mt=getmetatable(data)
  need(not mt or mt.__jsontype~="object",p,"expected an array; use array() for an empty array")
  local n=#t; for k in pairs(t) do need(type(k)=="number" and k%1==0 and k>=1 and k<=n,p,"expected a dense array") end
  for i=1,n do need(t[i]~=nil,p,"expected a dense array") end
  return t
end
local function numbers(t,n,p)
  seq(t,p);need(#t==n,p,"wrong coordinate count")
  for _,v in ipairs(t) do need(finite(v),p,"nonfinite coordinate") end
end
local function coordinates(v,n,p)
  if v.exact then
    need(v.point==nil,p,"point and exact coordinates cannot both be authoritative")
    local ok,err=pcall(require("pattern_exact").validate_point,v.exact,n)
    need(ok,p,"invalid exact coordinate: "..tostring(err))
  else numbers(v.point,n,p) end
end
local function bounds(t,p)
  numbers(t,4,p);need(t[3]>t[1] and t[4]>t[2],p,"expected positive bounds")
end
local function clone(v,seen,depth,count)
  local ty=type(v)
  if ty=="number" then
    need(finite(v),"data","nonfinite number")
    need(not math.type or math.type(v)~="integer" or (v>=-9007199254740991 and v<=9007199254740991),"data","integer exceeds portable exact range; use a string identity")
    return v
  elseif ty=="string" then
    need(utf8.len(v)~=nil,"data","invalid UTF-8; binary resources require explicit encoding")
    for _,cp in utf8.codes(v) do need(cp<=0x10ffff and (cp<0xd800 or cp>0xdfff),"data","invalid Unicode scalar value") end
    return v
  elseif ty=="boolean" or ty=="nil" then return v end
  need(ty=="table" and v~=json.null,"data","expected JSON data, without null/functions/userdata")
  v=stored[v] or v;seen=seen or {};depth=depth or 0;count=count or {n=0}
  need(not seen[v] and depth<64,"data","cyclic or excessively nested data")
  count.n=count.n+1;need(count.n<=100000,"data","data object budget exceeded")
  seen[v]=true
  local mt=getmetatable(v)
  need(mt==nil or (type(mt)=="table" and (mt.__jsontype=="array" or mt.__jsontype=="object")),"data","unsupported data metatable")
  if mt then for k in pairs(mt) do need(k=="__jsontype","data","executable/unknown data metatable field") end end
  local array=(mt and mt.__jsontype=="array") or (not mt and #v>0)
  if array then for i=1,#v do need(rawget(v,i)~=nil,"data","sparse array") end end
  local out=setmetatable({},{__jsontype=array and "array" or "object"})
  for k,x in pairs(v) do
    if array then need(type(k)=="number" and k%1==0 and k>=1 and k<=#v,"data","sparse or mixed array")
    else need(type(k)=="string","data","object keys must be strings");clone(k) end
    out[k]=clone(x,seen,depth+1,count)
  end
  seen[v]=nil;return out
end
local function freeze(v)
  if type(v)~="table" then return v end
  local data={};for k,x in pairs(v) do data[k]=freeze(x) end
  setmetatable(data,getmetatable(v))
  local proxy={};stored[proxy]=data
  return setmetatable(proxy,{__index=data,__newindex=function() fail("instance","immutable snapshot; construct a new record") end,
    __pairs=function() return next,data,nil end,__len=function() return #data end,__metatable=false})
end
function M.array(t) return setmetatable(t or {},{__jsontype="array"}) end
function M.plain(t) return clone(t) end
function M.snapshot(t) return freeze(clone(t)) end
local headers={kind=true,schema_version=true,id=true,extensions=true}
local function fields(t,allowed,p)
  local known={};for k in pairs(headers) do known[k]=true end
  for k in allowed:gmatch("%S+") do known[k]=true end
  for k in pairs(t) do need(known[k],p,"unknown key '"..tostring(k).."'") end
end
local function header(t,kind)
  need(type(t)=="table",kind,"expected record")
  need(t.kind==kind,kind,"wrong record kind")
  need(t.schema_version==1,kind,"unsupported schema version; explicit migration required")
  id(t.id,kind..".id")
end
local function ref(r,target,p)
  need(type(r)=="table",p,"expected versioned reference")
  need(r.id==target.id and r.version==target.version,p,"reference does not match definition")
end
local function list_ids(t,p)
  local found={};for _,s in ipairs(seq(t,p)) do id(s,p);need(not found[s],p,"duplicate ID "..s);found[s]=true end
  return found
end
local semantics={graph=true,strands=true,tiling=true,growth=true,field=true,text=true,curve3d=true}
local function definition(d)
  header(d,"definition")
  fields(d,"version family capabilities parameters units transforms assumptions validation", "definition")
  id(d.version,"definition.version");id(d.family,"definition.family")
  local tags=list_ids(d.capabilities,"definition.capabilities");need(next(tags),"definition","at least one semantic capability required")
  for tag in pairs(tags) do need(semantics[tag],"definition.capabilities","unsupported semantic tag "..tag) end
  need(d.units=="cm" or d.units=="mm" or d.units=="bp" or d.units=="unit","definition.units","unsupported explicit unit")
  need(type(d.transforms)=="table","definition.transforms","expected transformation policy")
  for _,k in ipairs({"metric_constrained","reflection","uniform_scale"}) do need(type(d.transforms[k])=="boolean","definition.transforms."..k,"expected boolean") end
  need(type(d.parameters)=="table","definition.parameters","expected parameter declarations")
  for name,p in pairs(d.parameters) do
    id(name,"parameter name");need(type(p)=="table","parameter."..name,"expected declaration")
    need(p.type=="number" or p.type=="integer" or p.type=="boolean" or p.type=="string","parameter."..name,"unsupported parameter type")
    local keys={type=true,minimum=true,maximum=true,enum=true,required=true}
    for k in pairs(p) do need(keys[k],"parameter."..name,"unknown declaration key "..k) end
    if p.required~=nil then need(type(p.required)=="boolean",name,"required must be boolean") end
    need((p.minimum==nil and p.maximum==nil) or p.type=="number" or p.type=="integer",name,"range is only valid for numeric parameters")
    if p.minimum~=nil then need(finite(p.minimum),name,"invalid minimum") end
    if p.maximum~=nil then need(finite(p.maximum),name,"invalid maximum") end
    if p.minimum and p.maximum then need(p.minimum<=p.maximum,name,"inverted parameter range") end
  end
  seq(d.assumptions,"definition.assumptions")
end
local function parameters(values,d)
  need(type(values)=="table","spec.parameters","expected parameters")
  for name in pairs(values) do need(d.parameters[name],"spec.parameters","unsupported control "..name) end
  for name,p in pairs(d.parameters) do
    local v=values[name]
    need(v~=nil or not p.required,"spec.parameters."..name,"required value missing")
    if v~=nil then
      local numeric=p.type=="number" or p.type=="integer"
      need(numeric and finite(v) or type(v)==p.type,"spec.parameters."..name,"wrong parameter type")
      if p.type=="integer" then need(v%1==0,name,"expected integer") end
      if p.minimum~=nil then need(v>=p.minimum,name,"below minimum") end
      if p.maximum~=nil then need(v<=p.maximum,name,"above maximum") end
      if p.enum then local match=false;for _,x in ipairs(seq(p.enum,name)) do if v==x then match=true end end;need(match,name,"unsupported value") end
    end
  end
end
local function spec(s,d)
  header(s,"specification");fields(s,"definition_ref parameters inputs document constraints seed style budget","specification")
  definition(d);ref(s.definition_ref,d,"spec.definition_ref");parameters(s.parameters,d)
  need(finite(s.seed) and s.seed%1==0 and s.seed>=0 and s.seed<2^31,"spec.seed","expected seed in 0..2^31-1")
  need(type(s.inputs)=="table" and type(s.constraints)=="table" and type(s.style)=="table","spec","expected explicit input, constraint and style objects")
  need(type(s.document)=="table" and s.document.unit=="cm","spec.document","document units must be cm")
  bounds(s.document.bounds,"spec.document.bounds")
  for _,r in ipairs(seq(s.document.protected_regions,"spec.document.protected_regions")) do bounds(r.bounds,"protected region");need(r.role=="protected_content","protected region","explicit role required") end
end
local function instance(x,d)
  header(x,"instance");fields(x,"definition_ref frame structures provenance validation","instance")
  definition(d);ref(x.definition_ref,d,"instance.definition_ref")
  need(type(x.frame)=="table" and (x.frame.dimension==2 or x.frame.dimension==3),"instance.frame","expected 2D or 3D frame")
  need(x.frame.unit==d.units and x.frame.handedness=="right","instance.frame","unit or orientation mismatch")
  numbers(x.frame.origin,x.frame.dimension,"instance.frame.origin");id(x.frame.id,"instance.frame.id")
  need(type(x.structures)=="table","instance.structures","expected capability-tagged structures")
  need(type(x.provenance)=="table" and x.provenance.generator==d.id and x.provenance.generator_version==d.version,"instance.provenance","generator identity/version required")
  local permitted, ids=list_ids(d.capabilities,"capabilities"), {[x.id]=true}
  local function add(t,p)
    local out={};for _,v in ipairs(seq(t,p)) do id(v.id,p);need(not ids[v.id],p,"duplicate semantic identity "..v.id);ids[v.id]=true;out[v.id]=v end;return out
  end
  local function exists(k,map,p) need(type(k)=="string" and map[k],p,"dangling semantic reference "..tostring(k)) end
  for tag in pairs(x.structures) do need(permitted[tag],"instance.structures","undeclared capability "..tag) end
  for tag in pairs(permitted) do need(type(x.structures[tag])=="table","instance.structures","missing capability "..tag) end
  local g=x.structures.graph
  if g then
    local vertices=add(g.vertices,"graph.vertices");local edges=add(g.edges,"graph.edges")
    for _,v in pairs(vertices) do coordinates(v,x.frame.dimension,"graph.vertex.point") end
    for _,e in pairs(edges) do exists(e.from,vertices,"graph.edge");exists(e.to,vertices,"graph.edge");need(e.from~=e.to,"graph.edge","self-loop needs a separately declared representation") end
  end
  local t=x.structures.tiling
  if t then
    need(x.frame.dimension==2,"tiling","expected 2D construction")
    local vs=add(t.vertices,"tiling.vertices");local es=add(t.edges,"tiling.edges");local cs=add(t.cells,"tiling.cells");local use={}
    for _,v in pairs(vs) do coordinates(v,2,"tiling.vertex.point") end
    for _,e in pairs(es) do exists(e.from,vs,"tiling.edge");exists(e.to,vs,"tiling.edge");exists(e.owner,cs,"tiling.edge.owner");need(e.role=="interior" or e.role=="patch_boundary","tiling.edge.role","unknown boundary role") end
    for _,c in pairs(cs) do
      id(c.prototype,"cell.prototype");need(c.chirality==1 or c.chirality==-1,"cell.chirality","expected signed orientation")
      need(c.chirality==1 or d.transforms.reflection,"cell.chirality","reflection prohibited by definition")
      for _,b in ipairs(seq(c.boundary,"cell.boundary")) do exists(b.edge,es,"cell.boundary");need(type(b.reversed)=="boolean","cell.boundary","edge direction required");use[b.edge]=use[b.edge] or {};use[b.edge][#use[b.edge]+1]={cell=c.id,reversed=b.reversed} end
    end
    for k,e in pairs(es) do
      local u=use[k] or {};need(#u==(e.role=="interior" and 2 or 1),"tiling.edge","wrong boundary incidence")
      need((u[1] and u[1].cell==e.owner) or (u[2] and u[2].cell==e.owner),"tiling.edge","owner is not incident")
      if #u==2 then need(u[1].cell~=u[2].cell and u[1].reversed~=u[2].reversed,"tiling.edge","shared boundary directions disagree") end
    end
    if t.hierarchy then
      local hs=add(t.hierarchy,"tiling.hierarchy")
      local parents={}
      for _,h in pairs(hs) do for _,child in ipairs(seq(h.children,"hierarchy.children")) do exists(child,cs[child] and cs or hs,"hierarchy.child");need(not parents[child],"hierarchy.child","multiple parents");parents[child]=h.id end end
      for k in pairs(cs) do need(parents[k],"hierarchy","cell missing from declared history") end
      for k in pairs(hs) do local seen={};local p=k;while p do need(not seen[p],"hierarchy","cyclic parent history");seen[p]=true;p=parents[p] end end
    end
  end
  local growth=x.structures.growth
  if growth then
    local ns=add(growth.nodes,"growth.nodes");local roots=list_ids(growth.roots,"growth.roots")
    for k in pairs(roots) do exists(k,ns,"growth.root") end
    for k,n in pairs(ns) do
      if n.parent then exists(n.parent,ns,"growth.parent");need(not roots[k],"growth","root has a parent") else need(roots[k],"growth","unlisted root") end
      coordinates(n,x.frame.dimension,"growth.point")
      local seen={};local p=k;while p do need(not seen[p],"growth","cyclic growth hierarchy");seen[p]=true;p=ns[p].parent end
    end
  end
  local strands=x.structures.strands
  if strands then
    local ss=add(strands.components,"strands.components");local crossings=add(strands.crossings,"strands.crossings");local ports=add(strands.ports,"strands.ports");local visits={}
    for _,p in pairs(ports) do exists(p.component,ss,"strand.port");coordinates(p,x.frame.dimension,"strand.port.point") end
    for _,c in pairs(crossings) do exists(c.over,ss,"crossing.over");exists(c.under,ss,"crossing.under");need(c.over~=c.under or c.self_crossing==true,"crossing","self crossing must be explicit");coordinates(c,2,"crossing.point") end
    for _,s in pairs(ss) do
      need(type(s.closed)=="boolean" and type(s.alternating)=="boolean","strand","closure and alternation policy required")
      local ends=list_ids(s.endpoints,"strand.endpoints");need(#s.endpoints==(s.closed and 0 or 2),"strand","wrong endpoint count")
      for k in pairs(ends) do exists(k,ports,"strand.endpoint");need(ports[k].component==s.id,"strand.endpoint","foreign endpoint") end
      local previous,first
      for _,e in ipairs(seq(s.encounters,"strand.encounters")) do
        exists(e.crossing,crossings,"strand.encounter");need(e.role=="over" or e.role=="under","strand.encounter","role required")
        need(crossings[e.crossing][e.role]==s.id,"strand.encounter","crossing belongs to another strand")
        local key=e.crossing..":"..e.role;need(not visits[key],"strand.encounter","duplicate crossing role");visits[key]=true
        if s.alternating and previous then need(previous~=e.role,"strand","incompatible alternation") end
        first=first or e.role;previous=e.role
      end
      if s.closed and s.alternating and previous then need(previous~=first,"strand","closure breaks alternation") end
    end
    for k in pairs(crossings) do need(visits[k..":over"] and visits[k..":under"],"crossing","incomplete crossing incidence") end
  end
  local text=x.structures.text
  if text then
    local runs=add(text.runs,"text.runs");local order=list_ids(text.reading_order,"text.reading_order")
    local n=0;for k,v in pairs(runs) do n=n+1;need(order[k],"text.reading_order","missing text run");need(type(v.text)=="string" and (v.direction=="ltr" or v.direction=="rtl"),"text.run","text and explicit direction required") end
    need(#text.reading_order==n,"text.reading_order","duplicate, missing or foreign run")
  end
  local curves=x.structures.curve3d
  if curves then need(x.frame.dimension==3,"curve3d","3D frame required");local vs=add(curves.vertices,"curve3d.vertices");local cs=add(curves.curves,"curve3d.curves");for _,v in pairs(vs) do coordinates(v,3,"curve3d.point") end;for _,c in pairs(cs) do exists(c.from,vs,"curve3d.from");exists(c.to,vs,"curve3d.to") end end
  local field=x.structures.field
  if field then
    need(field.representation=="samples","field.representation","unsupported representation in contract v1")
    need(type(field.domain)=="table","field.domain","domain required");bounds(field.domain.bounds,"field.domain.bounds")
    local samples=add(field.samples,"field.samples");for _,s in pairs(samples) do coordinates(s,2,"field.point");numbers(s.vector,2,"field.vector");need(finite(s.density) and s.density>=0,"field.density","invalid density") end
  end
  return ids
end
local function view_settings(v,d,dimension)
  need(v.unit=="cm","view.unit","document view must use cm")
  numbers(v.transform,6,"view.transform");bounds(v.crop,"view.crop")
  for _,r in ipairs(seq(v.protected_regions,"view.protected_regions")) do bounds(r.bounds,"protected region");need(r.role=="protected_content","protected region","explicit role required") end
  need(type(v.derived)=="boolean","view.derived","explicit derived-view flag required")
  local a,b,c,e=v.transform[1],v.transform[2],v.transform[3],v.transform[4]
  local det=a*e-b*c;need(math.abs(det)>M.TOLERANCE,"view.transform","singular or sub-tolerance transform")
  if dimension==3 then need(v.derived and type(v.projection)=="table","view.projection","3D lowering requires an explicit derived projection") end
  if v.projection then numbers(v.projection.matrix,16,"projection.matrix");need(v.projection.depth_policy=="all_curves" or v.projection.depth_policy=="depth_sorted","projection.depth_policy","explicit supported visibility policy required") end
  if v.derived then need(v.validity=="visualization_only","view.validity","derived views must disclaim construction-metric validity")
  else
    need(v.validity=="construction_preserved" and not v.projection,"view.validity","projection requires an explicit derived view")
    if d.transforms.metric_constrained then
      local q=a*a+b*b;local r=c*c+e*e
      need(math.abs(q-r)<=M.TOLERANCE*math.max(1,q,r) and math.abs(a*c+b*e)<=M.TOLERANCE*math.max(1,q,r),"view.transform","nonuniform stretch/shear changes the metric")
      if not d.transforms.uniform_scale then need(math.abs(q-1)<=M.TOLERANCE,"view.transform","scale prohibited") end
    end
    need(det>0 or d.transforms.reflection,"view.transform","reflection prohibited")
  end
end
local function view(v,x,d)
  instance(x,d)
  header(v,"view");fields(v,"instance_ref unit transform crop protected_regions derived validity projection","view")
  need(v.instance_ref==x.id,"view.instance_ref","wrong instance")
  view_settings(v,d,x.frame.dimension)
end
function M.view_settings(t,d,dimension)
  definition(d);local v=clone(t)
  fields(v,"unit transform crop protected_regions derived validity projection","view settings")
  need(dimension==2 or dimension==3,"view settings","dimension required")
  view_settings(v,d,dimension);return freeze(v)
end
local function scene(s,x,v,d)
  view(v,x,d)
  header(s,"scene");fields(s,"instance_ref view_ref unit operations resources validity clip reading_order","scene")
  need(s.instance_ref==x.id and s.view_ref==v.id,"scene","wrong semantic source")
  need(s.unit==v.unit and s.validity==v.validity,"scene","unit or validity scope mismatch")
  need(type(s.clip)=="table","scene.clip","clip metadata required")
  bounds(s.clip.bounds,"scene.clip.bounds");seq(s.clip.protected_regions,"scene.clip.protected_regions")
  need(M.serialize(s.clip.bounds)==M.serialize(v.crop) and M.serialize(s.clip.protected_regions)==M.serialize(v.protected_regions),"scene.clip","view crop/protected regions must survive lowering")
  require("pattern_draw").validate_scene(s,instance(x,d),x.structures.text)
end
local function build(r)
  header(r,"build_record");fields(r,"status inputs source runtime seed dependencies lineage validation outputs diagnostics budgets","build_record")
  need(r.status=="complete" or r.status=="failed" or r.status=="cancelled" or r.status=="partial","build_record.status","unknown status")
  need(type(r.source)=="table" and type(r.runtime)=="table" and type(r.dependencies)=="table","build_record","source/runtime/dependencies required")
  id(r.source.revision,"build_record.source.revision");id(r.runtime.name,"build_record.runtime.name");id(r.runtime.version,"build_record.runtime.version")
  need(finite(r.seed) and r.seed%1==0 and r.seed>=0 and r.seed<2^31,"build_record.seed","invalid seed")
  seq(r.inputs,"build_record.inputs");seq(r.lineage,"build_record.lineage");seq(r.outputs,"build_record.outputs");seq(r.diagnostics,"build_record.diagnostics")
  need(type(r.validation)=="table","build_record.validation","validation receipt required")
  if r.status=="complete" then
    need(r.validation.status=="passed" and #seq(r.validation.checks,"validation.checks")>0 and #r.outputs>0 and #r.inputs>0,"build_record","complete output needs actual validation and input/output evidence")
    local function digest(v) return type(v)=="string" and #v==64 and not v:find('[^0-9a-f]') end
    need(digest(r.source.digest),"build_record.source","source manifest digest required")
    for _,list in ipairs({r.inputs,r.outputs}) do for _,item in ipairs(list) do need(type(item)=="table" and digest(item.sha256),"build_record","exact input/output byte digests required") end end
  else need(#r.diagnostics>0,"build_record","unfinished outcomes require diagnostics") end
end
local function make(kind,data,check,...)
  local t=clone(data);need(type(t)=="table",kind,"expected data object");t.kind=t.kind or kind;t.schema_version=t.schema_version or 1
  check(t,...);return freeze(t)
end
function M.definition(t) return make("definition",t,definition) end
function M.specification(t,d) return make("specification",t,spec,d) end
function M.instance(t,d) return make("instance",t,instance,d) end
function M.view(t,x,d) return make("view",t,view,x,d) end
function M.scene(t,x,v,d) return make("scene",t,scene,x,v,d) end
function M.build_record(t) return make("build_record",t,build) end
function M.validate(kind,t,...)
  local checks={definition=definition,specification=spec,instance=instance,view=view,scene=scene,build_record=build}
  if not checks[kind] then return {ok=false,errors={"unknown record kind"}} end
  local args={...}
  local ok,err=pcall(function() return checks[kind](clone(t),table.unpack(args)) end)
  return {ok=ok,errors=ok and {} or {tostring(err)}}
end
-- Portable finite-number spelling; stable key order. Recipe/hash domain rules
-- and explicit version migrations are the stage 04 boundary.
function M.serialize(record)
  local function encode(v)
    if type(v)=="string" then return json.quotestring(v)
    elseif type(v)=="number" then
      if v==0 then return "0" end
      local s=string.format("%.17g",v):gsub(",","."):lower()
      return (s:gsub("e([+-]?)0*(%d+)",function(sign,n) return "e"..(sign=="-" and "-" or "+")..n end))
    elseif type(v)=="boolean" then return tostring(v) end
    local out={};local mt=getmetatable(v)
    if mt and mt.__jsontype=="array" then for i=1,#v do out[i]=encode(v[i]) end;return "["..table.concat(out,",").."]" end
    local keys={};for k in pairs(v) do keys[#keys+1]=k end;table.sort(keys,M.byte_less)
    for _,k in ipairs(keys) do out[#out+1]=json.quotestring(k)..":"..encode(v[k]) end
    return "{"..table.concat(out,",").."}"
  end
  return encode(clone(record))
end
function M.byte_less(a,b)
  for i=1,math.min(#a,#b) do local x,y=a:byte(i),b:byte(i);if x~=y then return x<y end end
  return #a<#b
end
function M.deserialize(text,kind,...)
  need(type(text)=="string" and #text<=2*1024*1024,"JSON","input exceeds contract byte limit")
  local value=require("pattern_parse").decode(text)
  local kinds={definition=true,specification=true,instance=true,view=true,scene=true,build_record=true}
  need(kinds[kind],"JSON","unknown constructor")
  return M[kind](value,...)
end
return M
