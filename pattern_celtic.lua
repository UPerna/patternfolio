-- Independent implementation of Kaplan and Cohen (2003), sections 3.1-3.3 and 3.5.
local G=require("pattern_geometry")
local N=require("pattern_predicates")
local M={}
local function fail(code,subject) error(code..": "..tostring(subject),0) end
local function valid_id(x)return type(x)=="string" and #x<=48 and x:match("^[%w_-]+$")end
local function coord(x)return type(x)=="number" and x==x and math.abs(x)<=1000 end
local function vec(a,b)return{b[1]-a[1],b[2]-a[2]}end
local function norm(v)return math.sqrt(v[1]^2+v[2]^2)end
local function unit(v)local n=norm(v);return{v[1]/n,v[2]/n}end
local function perp(v)return{-v[2],v[1]}end
local function sum(a,b,s)return{a[1]+s*b[1],a[2]+s*b[2]}end
local function near(a,b)return norm(vec(a,b))<1e-10 end
local function sorted(t)local a={}for k in pairs(t)do a[#a+1]=k end;table.sort(a);return a end
local orient=N.orient2d
local function on(a,b,p)return p[1]>=math.min(a[1],b[1]) and p[1]<=math.max(a[1],b[1])and p[2]>=math.min(a[2],b[2])and p[2]<=math.max(a[2],b[2])end
local function contact(a,b,c,d)
 local x,y,z,w=orient(a,b,c),orient(a,b,d),orient(c,d,a),orient(c,d,b)
 return (x<0 and y>0 or x>0 and y<0)and(z<0 and w>0 or z>0 and w<0)
  or x==0 and on(a,b,c)or y==0 and on(a,b,d)or z==0 and on(c,d,a)or w==0 and on(c,d,b)
end
local function xor(a,b)return (a+b)%2 end

-- Nodes are midpoint traversals. At each junction pair the two sides
-- bounding each angular sector. Cutting a sector makes two named ends.
function M.topology(scaffold)
 local V,E,H,join,ports,cross,inc={},{},{},{},{},{},{}
 local vv,ee=scaffold.vertices,scaffold.edges
 if type(vv)~="table"or type(ee)~="table"or #vv<2 or #vv>128 or #ee<1 or #ee>192 then fail("knot-scaffold-budget","vertices/edges")end
 for _,v in ipairs(vv)do
  if not valid_id(v.id)or V[v.id]or not v.point or not coord(v.point[1])or not coord(v.point[2])then fail("knot-vertex",v.id)end
  for _,p in pairs(V)do if near(p,v.point)then fail("knot-coincident-vertices",v.id)end end
  V[v.id]={v.point[1],v.point[2]};inc[v.id]={}
 end
 for _,e in ipairs(ee)do
  local a,b=e.from,e.to
  if not valid_id(e.id)or E[e.id]or a==b or not V[a]or not V[b]then fail("knot-edge",e.id)end
  if b<a then a,b=b,a end
  local p,q=V[a],V[b];local m=sum(p,vec(p,q),.5)
  for k,r in pairs(V)do if k~=a and k~=b and contact(p,q,r,r)then fail("knot-vertex-on-edge",e.id.."/"..k)end end
  for k,f in pairs(E)do
   if a==f.a and b==f.b then fail("knot-duplicate-edge",e.id)end
   if a~=f.a and a~=f.b and b~=f.a and b~=f.b and contact(p,q,V[f.a],V[f.b])then fail("knot-nonplanar",e.id.."/"..k)end
  end
  E[e.id]={a=a,b=b,point=m}
  cross[e.id]={id=e.id,point=m,branches={e.id.."/L",e.id.."/R"}}
  for _,ends in ipairs{{a,b},{b,a}}do
   local at,other=ends[1],ends[2];local u=unit(vec(m,V[at]));local n=perp(u);local base=e.id.."/"..at
   inc[at][#inc[at]+1]={base=base,angle=math.atan(-u[2],-u[1]),edge=e.id}
   for _,s in ipairs{"L","R"}do
    local d=unit(sum(u,n,s=="L"and 1 or -1))
    H[base.."/"..s]={at=at,edge=e.id,side=s,point=m,tangent=d,across=e.id.."/"..other.."/"..s,branch=e.id.."/"..s}
   end
  end
 end
 local cuts={}
 for _,c in ipairs(scaffold.open_sectors or {})do
  local k=tostring(c.vertex).."/"..tostring(c.edge)
  if cuts[k]then fail("knot-duplicate-port",k)end;cuts[k]=true
 end
 for k,list in pairs(inc)do
  if #list==0 then fail("knot-isolated-vertex",k)end
  table.sort(list,function(a,b)return a.angle<b.angle end)
  for i,a in ipairs(list)do
   local b=list[i%#list+1];local x,y=a.base.."/R",b.base.."/L";local key=k.."/"..a.edge
   if cuts[key]then
    cuts[key]=nil
    for j,h in ipairs{x,y}do
     local t=H[h];ports[h]={id="port/"..key.."/"..j,point=sum(t.point,t.tangent,.26*norm(vec(t.point,V[k]))),vertex=k,half=h}
    end
   else join[x]=y;join[y]=x end
  end
 end
 for k in pairs(cuts)do fail("knot-unknown-port",k)end
 local seen,components={},{}
 local function walk(h)
  local start=h;local seq={}
  repeat
   local inhalf=H[h];local out=inhalf.across
   if seen[h]or seen[out]then fail("knot-incidence",h)end
   seen[h],seen[out]=true,true
   seq[#seq+1]={branch=inhalf.branch,crossing=inhalf.edge,enter=h,leave=out}
   h=join[out]
  until not h or h==start
  local c={id="strand/"..start,closed=h==start,visits=seq,ends={}}
  if not c.closed then c.ends={ports[start].id,ports[seq[#seq].leave].id}end
  components[#components+1]=c
 end
 for _,h in ipairs(sorted(ports))do if not seen[h]then walk(h)end end
 for _,h in ipairs(sorted(H))do if not seen[h]then walk(h)end end
 local adj,values={},{}
 local function link(a,b,x)
  adj[a]=adj[a]or{};adj[b]=adj[b]or{}
  adj[a][#adj[a]+1]={b,x};adj[b][#adj[b]+1]={a,x}
 end
 for _,c in pairs(cross)do link(c.branches[1],c.branches[2],1)end
 for _,c in ipairs(components)do
  for i,v in ipairs(c.visits)do
   local n=c.visits[i+1]or c.closed and c.visits[1]
   if n then link(v.branch,n.branch,1)end
  end
 end
 local pins=scaffold.above or {}
 for k,b in pairs(pins)do
  if not cross[k]or b~="L"and b~="R"then fail("knot-invalid-over-request",k)end
  link("@phase",k.."/"..b,0)
 end
 local function solve(start,val)
  local q={start};values[start]=val;local i=1
  while i<=#q do
   local a=q[i];i=i+1
   for _,e in ipairs(adj[a])do
    local x=xor(values[a],e[2])
    if values[e[1]]==nil then values[e[1]]=x;q[#q+1]=e[1]
    elseif values[e[1]]~=x then fail("knot-incompatible-alternation",a.."/"..e[1])end
   end
  end
 end
 if adj["@phase"]then solve("@phase",1);values["@phase"]=nil end
 for _,k in ipairs(sorted(adj))do if k~="@phase"and values[k]==nil then solve(k,1)end end
 for _,c in pairs(cross)do c.above=values[c.branches[1]]==1 and c.branches[1]or c.branches[2]end
 return{vertices=V,crossings=cross,half_nodes=H,connections=join,ports=ports,components=components}
end
local function cubic(a,b,c,d)return{a,b,c,d}end
local function lerp(a,b,t)return sum(a,vec(a,b),t)end
local function split(c,t)
 local a,b,d=lerp(c[1],c[2],t),lerp(c[2],c[3],t),lerp(c[3],c[4],t)
 local x,y=lerp(a,b,t),lerp(b,d,t);local m=lerp(x,y,t)
 return cubic(c[1],a,x,m),cubic(m,y,d,c[4])
end
local function evaluate(c,t)local a=split(c,t);return a[4]end
local function direction_curve(p,u,q,v,s)
 local h=norm(vec(p,q))*s/3
 return cubic(p,sum(p,u,h),sum(q,v,h),q)
end
local function line(a,b)return cubic(a,lerp(a,b,1/3),lerp(a,b,2/3),b)end
local function curves(t,scale)
 local result={}
 local tuned={}
 local function dot(u,v)return u[1]*v[1]+u[2]*v[2]end
 for _,component in ipairs(t.components)do
  local seq=component.visits
  for i,v in ipairs(seq)do
   local prev=seq[i-1]or component.closed and seq[#seq]
   local nextv=seq[i+1]or component.closed and seq[1]
   local h=t.half_nodes[v.leave];local raw=h.tangent
   local a=prev and t.crossings[prev.crossing].point or t.ports[v.enter].point
   local b=nextv and t.crossings[nextv.crossing].point or t.ports[v.leave].point
   local chord=vec(a,b)
   if norm(chord)>1e-9 then
    local target=unit(chord);local vnext=nextv and t.half_nodes[nextv.leave].tangent or raw
    local weight=.14*(dot(vnext,raw)+1)/2
    raw=unit(lerp(raw,target,weight))
   end
   tuned[v.leave]=raw;tuned[v.enter]={-raw[1],-raw[2]}
  end
 end
 local function add(strand,c,a,b)
  result[#result+1]={strand=strand,c=c,a=a,b=b}
 end
 for _,component in ipairs(t.components)do
  local seq=component.visits
  if not component.closed then
   local h=seq[1].enter;add(component.id,line(t.ports[h].point,t.half_nodes[h].point),nil,h)
  end
  for i,visit in ipairs(seq)do
   local nextvisit=seq[i+1]or component.closed and seq[1]
   local h=visit.leave;local a=t.half_nodes[h]
   if nextvisit then
    local j=nextvisit.enter;local b=t.half_nodes[j]
    local c
    if near(a.point,b.point)then
     local v=t.vertices[a.at];local k=norm(vec(a.point,v))*1.42*scale
     c=cubic(a.point,sum(a.point,a.tangent,k),sum(b.point,b.tangent,k),b.point)
    else local u,v=tuned[h],tuned[j];local angle_scale=.75+.25*(1-dot(u,v))/2;c=direction_curve(a.point,u,b.point,v,scale*angle_scale)end
    add(component.id,c,h,j)
   else add(component.id,line(a.point,t.ports[h].point),h,nil)end
  end
 end
 return result
end
local function endpoint_edge(t,h)return h and t.half_nodes[h].edge end
local function check_curves(t,cs,width)
 local sampled={};local count=16
 for k,r in ipairs(cs)do
  local points={}
  for i=0,count do points[i+1]=evaluate(r.c,i/count)end
  sampled[k]=points
 end
 for i,a in ipairs(sampled)do for j=i,#sampled do
  local b=sampled[j];local ca,cb=cs[i],cs[j]
  for k=1,count do for n=(i==j and k+2 or 1),count do
   local x,y,z,w=a[k],a[k+1],b[n],b[n+1]
   local ae=k==1 and endpoint_edge(t,ca.a)or k==count and endpoint_edge(t,ca.b)
   local be=n==1 and endpoint_edge(t,cb.a)or n==count and endpoint_edge(t,cb.b)
   local shared=ae and ae==be
   if not shared then
    local pad=width
    if math.max(x[1],y[1])+pad>=math.min(z[1],w[1])and math.max(z[1],w[1])+pad>=math.min(x[1],y[1])
      and math.max(x[2],y[2])+pad>=math.min(z[2],w[2])and math.max(z[2],w[2])+pad>=math.min(x[2],y[2])then
     if contact(x,y,z,w)then return nil,"knot-smoothing-collision",i.."/"..j end
     if i~=j and width>0 then
      local dist=math.min(G.point_segment_distance(x,z,w),G.point_segment_distance(y,z,w),
       G.point_segment_distance(z,x,y),G.point_segment_distance(w,x,y))
      local joint=false
      for _,u in ipairs{ca.a or false,ca.b or false}do for _,v in ipairs{cb.a or false,cb.b or false}do
       local e=endpoint_edge(t,u)
       if e and e==endpoint_edge(t,v)then
        if t.half_nodes[u].branch==t.half_nodes[v].branch then joint=true end
        local p=t.crossings[e].point
        local function reach(c)
         local a,b=c[1],c[4]
         if near(a,b)then return norm(vec(a,c[2]))end
         return norm(vec(a,b))
        end
        local neighborhood=.22*math.max(reach(ca.c),reach(cb.c))
        if math.min(norm(vec(x,p)),norm(vec(y,p)))<neighborhood and math.min(norm(vec(z,p)),norm(vec(w,p)))<neighborhood then joint=true end
       end
      end end
      if not joint and dist<width then return nil,"knot-ribbon-clearance",i.."/"..j end
     end
    end
   end
  end end
 end end
 return true
end
function M.smooth(t,scale)
 local cs=curves(t,scale or 1)
 local ok,code,detail=check_curves(t,cs,0)
 if not ok then fail(code,detail)end
 return cs
end
local function gap_parameter(c,dist,reverse)
 local p=reverse and c[4]or c[1]
 if norm(vec(p,evaluate(c,.5)))<dist then fail("knot-ribbon-clearance","crossing gaps meet")end
 local lo,hi=0,.5
 for _=1,24 do
  local t=(lo+hi)/2;local q=evaluate(c,reverse and 1-t or t)
  if norm(vec(p,q))<dist then lo=t else hi=t end
 end
 return reverse and 1-hi or hi
end
function M.ribbon(t,cs,width,halo)
 if not coord(width)or width<=0 or not coord(halo)or halo<0 then fail("knot-ribbon-style","width/halo")end
 local ok,code,detail=check_curves(t,cs,width+halo)
 if not ok then fail(code,detail)end
 local out={}
 local function under(h)local n=h and t.half_nodes[h];return n and t.crossings[n.edge].above~=n.branch end
 for _,r in ipairs(cs)do
  local c=r.c
  local a=under(r.a)and gap_parameter(c,width/2+halo,false)or 0
  local b=under(r.b)and gap_parameter(c,width/2+halo,true)or 1
  if a>=b then fail("knot-ribbon-clearance","empty connector")end
  if b<1 then c=split(c,b)end
  if a>0 then local _,q=split(c,a/b);c=q end
  out[#out+1]={strand=r.strand,curve=c}
 end
 return out
end
local P=require("pattern")
local function structures(s,t)
 local vertices,edges,components,crossings,ports=P.array(),P.array(),P.array(),P.array(),P.array()
 local branch,owners={},{ }
 for _,k in ipairs(sorted(t.vertices))do vertices[#vertices+1]={id="vertex/"..k,point=t.vertices[k]}end
 for _,e in ipairs(s.edges)do
  local a,b=e.from,e.to;if b<a then a,b=b,a end
  edges[#edges+1]={id="edge/"..e.id,from="vertex/"..a,to="vertex/"..b}
 end
 table.sort(edges,function(a,b)return a.id<b.id end)
 for _,c in ipairs(t.components)do
  local encounters=P.array()
  for _,v in ipairs(c.visits)do
   branch[v.branch]=c.id
   encounters[#encounters+1]={crossing="crossing/"..v.crossing,role=t.crossings[v.crossing].above==v.branch and "over"or"under",
    branch=v.branch,enter=v.enter,leave=v.leave}
  end
  for _,port in ipairs(c.ends)do owners[port]=c.id end
  components[#components+1]={id=c.id,closed=c.closed,alternating=true,encounters=encounters,endpoints=c.closed and P.array()or c.ends}
 end
 for _,k in ipairs(sorted(t.crossings))do
  local c=t.crossings[k];local under=c.above==c.branches[1]and c.branches[2]or c.branches[1]
  crossings[#crossings+1]={id="crossing/"..k,point=c.point,over=branch[c.above],under=branch[under],
   over_branch=c.above,under_branch=under,self_crossing=branch[c.above]==branch[under]}
 end
 for _,k in ipairs(sorted(t.ports))do
  local p=t.ports[k];ports[#ports+1]={id=p.id,component=owners[p.id],point=p.point,tangent=t.half_nodes[k].tangent,role="explicit_open_sector",half=k}
 end
 return{graph={vertices=vertices,edges=edges},strands={components=components,crossings=crossings,ports=ports}}
end
local function attachment(s,t)
 if not s.botanical_port then return nil end
 for h,p in pairs(t.ports)do if p.id==s.botanical_port then
  local u=t.half_nodes[h].tangent;local n=perp(u)
  return{port=p.id,root=p.point,points={p.point,sum(p.point,u,.28),sum(sum(p.point,u,.58),n,.13),sum(sum(p.point,u,.88),n,.4)}}
 end end
 fail("knot-attachment-port",s.botanical_port)
end
function M.definition()
 return P.definition({id="strand/celtic",version="1",family="planar-celtic",units="cm",capabilities={"graph","strands"},
  parameters={smoothing={type="number",minimum=.4,maximum=3}},transforms={metric_constrained=true,reflection=false,uniform_scale=true},
  assumptions={"Straight-line planar embedding supplied explicitly; crossings at edge midpoints",
   "Angular sector traversal and Hermite connectors; alternating over/under as binary constraints",
   "Open sectors are authored cuts; clipping preserves topology; clearance sampled at 16 segments per connector"}})
end
local function validate(x)
 local k=x.extensions.celtic
 local t=M.topology(P.plain(k.scaffold))
 assert(P.serialize(structures(k.scaffold,t))==P.serialize(x.structures),"knot-strand-record-mismatch")
 assert(P.serialize(attachment(k.scaffold,t)or {})==P.serialize(k.attachment or {}),"knot-attachment-mismatch")
 local curves=M.smooth(t,k.smoothing)
 assert(P.serialize(curves)==P.serialize(k.curves),"knot-smoothing-record-mismatch")
 return {ok=true,checks={'reconstructed traversal','crossing phase and attachments','Hermite connectors'}}
end
function M.validate(x)return validate(P.instance(P.plain(x),M.definition()))end
local function lower(x,v,style,c)
 for k in pairs(style)do
  if k~="width"and k~="halo"and k~="stroke"then fail("knot-style",k)end
 end
 local k=x.extensions.celtic;local t=M.topology(P.plain(k.scaffold))
 local width,halo=style.width or .085,style.halo or .035
 local ribbons=M.ribbon(t,k.curves,width,halo)
 local ops={};local matrix=P.plain(v.transform)
 local last,last_end
 for _,p in ipairs(ribbons)do
  local a,b,d,e=table.unpack(p.curve)
  if not last or last.semantic_ref~=p.strand or not near(last_end,a)then
   last={op="path",semantic_ref=p.strand,commands={{"M",a[1],a[2]}},
    transform=matrix,paint={stroke=style.stroke or {.09,.22,.43},stroke_width=width}}
   ops[#ops+1]=last
  end
  last.commands[#last.commands+1]={"C",b[1],b[2],d[1],d[2],e[1],e[2]}
  last_end=e
 end
 if k.attachment then
  local ink,flora=require("ink"),require("flora");local a=k.attachment
  local actual=ink.capture(function()
   ink.set_ink(.15,.39,.31);ink.set_accent(.75,.48,.21);ink.set_lift(0);ink.set_color_mode("color")
   flora.stem(P.plain(a.points),width/2,.012)
   local tip=a.points[#a.points]
   ink.push();ink.translate(tip[1],tip[2]);ink.scale(.46);flora.leaf(ink.rng(2741),{w=.3,bend=.15,lobes=3,depth=.35,tone=.36});ink.pop()
  end)
  for _,op in ipairs(actual)do
   if op.op=="path"then op.semantic_ref=a.port end; if op.op~="pop_clip"then op.transform=G.compose(matrix,op.transform or {1,0,0,1,0,0})end;ops[#ops+1]=op
  end
 end
 return{id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
  clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end
function M.register(registry)
 local d=M.definition()
 registry:register(d,{validate_inputs=function(s)
  local i=P.plain(s.inputs);for k in pairs(i)do if k~="scaffold"then return false end end;return type(i.scaffold)=="table" and next(P.plain(s.constraints))==nil
 end,generate=function(s,c)
  local scaffold=P.plain(s.inputs.scaffold);local t=M.topology(scaffold)
  c:consume("objects",#scaffold.vertices+#scaffold.edges*8)
  c:consume("operations",(#scaffold.edges)^2*1024)
  local scale=s.parameters.smoothing or 1;local cs=M.smooth(t,scale)
  return{id=s.id.."/knot",definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures=structures(scaffold,t),
   provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction="kaplan-cohen-planar-hermite-v1"},
   extensions={celtic={scaffold=scaffold,smoothing=scale,curves=cs,attachment=attachment(scaffold,t)}}}
 end,validate=validate,lower=lower})
 return d
end
return M










