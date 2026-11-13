-- Explicit document-unit geometry. Exact topological predicates are separate
-- from policy-bounded floating-point coordinates and proximity decisions.
local P,N=require("pattern"),require("pattern_predicates")
local E=require("pattern_exact")
local regions=setmetatable({},{__mode="k"})
local G={VERSION="geometry-v1"};local eps=2^-52
local function number(n) assert(type(n)=="number" and n==n and math.abs(n)<math.huge,"finite number required");return n+0.0 end
local function point(p)
  assert(type(p)=="table" and #p==2,"2D point required")
  for k in pairs(p) do assert(k==1 or k==2,"unknown point coordinate field") end
  for _,v in ipairs(p) do number(v);assert(math.abs(v)<=1e50 and (v==0 or math.abs(v)>=1e-50),"geometry coordinate outside admitted range; normalize frame") end
  return {p[1]+0.0,p[2]+0.0}
end
local function same(a,b) return a[1]==b[1] and a[2]==b[2] end
local function norm(a,b) return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2) end
local function interpolate(a,b,t) return {a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2])} end
function G.policy(unit,scale,relative,absolute)
  assert(unit=="cm" or unit=="mm" or unit=="bp" or unit=="unit","explicit supported unit required")
  scale=number(scale);relative=number(relative or 1e-10);absolute=number(absolute or 0)
  assert(scale>=1e-40 and scale<=1e40 and relative>=0 and relative<=0.01 and absolute>=0,"invalid tolerance policy")
  return P.snapshot({unit=unit,scale=scale,relative=relative,absolute=absolute})
end
function G.tolerance(policy,points)
  assert(policy and policy.scale and policy.unit,"explicit geometry policy required")
  local magnitude=policy.scale
  for _,p in ipairs(points or {}) do p=point(p);magnitude=math.max(magnitude,math.abs(p[1]),math.abs(p[2])) end
  return math.max(policy.absolute,policy.relative*policy.scale,32*eps*magnitude)
end
function G.transform(p,m)
  p=point(p);assert(type(m)=="table" and #m==6,"affine [a,b,c,d,tx,ty] required");for _,v in ipairs(m) do number(v) end
  return point({m[1]*p[1]+m[3]*p[2]+m[5],m[2]*p[1]+m[4]*p[2]+m[6]})
end
function G.compose(a,b)
  for _,m in ipairs({a,b}) do assert(#m==6,"affine matrix required");for _,v in ipairs(m) do number(v) end end
  local out={a[1]*b[1]+a[3]*b[2],a[2]*b[1]+a[4]*b[2],a[1]*b[3]+a[3]*b[4],a[2]*b[3]+a[4]*b[4],a[1]*b[5]+a[3]*b[6]+a[5],a[2]*b[5]+a[4]*b[6]+a[6]}
  for _,v in ipairs(out) do number(v) end;return out
end
function G.inverse(m,policy)
  assert(type(m)=="table" and #m==6,"affine matrix required");for _,v in ipairs(m) do number(v) end
  G.tolerance(policy)
  local d=m[1]*m[4]-m[2]*m[3];assert(d~=0 and d==d and math.abs(d)<math.huge,"singular/nonfinite affine transform")
  local error=8*eps*(math.abs(m[1]*m[4])+math.abs(m[2]*m[3]))/math.abs(d)
  assert(error<=math.max(policy.relative,32*eps),"inverse conditioning exceeds requested numerical policy")
  local a,b,c,e=m[4]/d,-m[2]/d,-m[3]/d,m[1]/d
  local out={a,b,c,e,-a*m[5]-c*m[6],-b*m[5]-e*m[6]}
  for _,v in ipairs(out) do number(v) end;return out,{relative_error_bound=error}
end
local function between(p,a,b)
  return p[1]>=math.min(a[1],b[1]) and p[1]<=math.max(a[1],b[1]) and p[2]>=math.min(a[2],b[2]) and p[2]<=math.max(a[2],b[2])
end
function G.parameter(p,a,b)
  local axis=math.abs(b[1]-a[1])>=math.abs(b[2]-a[2]) and 1 or 2
  assert(b[axis]~=a[axis],"zero-length segment has no parameter");return (p[axis]-a[axis])/(b[axis]-a[axis])
end
function G.segment_intersection(a,b,c,d,policy)
  a,b,c,d=point(a),point(b),point(c),point(d);local tol=G.tolerance(policy,{a,b,c,d})
  if same(a,b) or same(c,d) then return {kind="degenerate",reason="zero_length_segment",tolerance=tol} end
  local o1,o2,o3,o4=N.orient2d(a,b,c),N.orient2d(a,b,d),N.orient2d(c,d,a),N.orient2d(c,d,b)
  if o1==0 and o2==0 then
    local axis=math.abs(b[1]-a[1])>=math.abs(b[2]-a[2]) and 1 or 2
    local aa,bb=a,b;if aa[axis]>bb[axis] then aa,bb=bb,aa end
    local cc,dd=c,d;if cc[axis]>dd[axis] then cc,dd=dd,cc end
    local lo=aa[axis]>=cc[axis] and aa or cc;local hi=bb[axis]<=dd[axis] and bb or dd
    if lo[axis]>hi[axis] then return {kind="none",exact_classification=true} end
    if same(lo,hi) then return {kind="point",classification="endpoint",point=point(lo),t=G.parameter(lo,a,b),u=G.parameter(lo,c,d),error_bound=0} end
    return {kind="overlap",from=point(lo),to=point(hi),exact_classification=true}
  end
  for _,case in ipairs({{o1,c,a,b},{o2,d,a,b},{o3,a,c,d},{o4,b,c,d}}) do
    if case[1]==0 and between(case[2],case[3],case[4]) then
      local p=case[2];return {kind="point",classification="endpoint",point=point(p),t=G.parameter(p,a,b),u=G.parameter(p,c,d),error_bound=0}
    end
  end
  if o1*o2>=0 or o3*o4>=0 then return {kind="none",exact_classification=true} end
  local va=N.determinant_value(c,d,a);local vb=N.determinant_value(c,d,b)
  local vc=N.determinant_value(a,b,c);local vd=N.determinant_value(a,b,d)
  local t,u=va/(va-vb),vc/(vc-vd);local p,q=interpolate(a,b,t),interpolate(c,d,u)
  local error=norm(p,q)+16*eps*math.max(policy.scale,math.abs(p[1]),math.abs(p[2]))
  if error>tol then return {kind="unresolved",reason="intersection_coordinate_precision",exact_classification="proper_crossing",error_bound=error,tolerance=tol} end
  return {kind="point",classification="proper",point={(p[1]+q[1])/2,(p[2]+q[2])/2},t=t,u=u,error_bound=error,exact_classification=true}
end
function G.point_segment_distance(p,a,b)
  p,a,b=point(p),point(a),point(b);local dx,dy=b[1]-a[1],b[2]-a[2];local length=dx*dx+dy*dy
  assert(length>0,"distance to degenerate segment must be handled as a point")
  local t=math.max(0,math.min(1,((p[1]-a[1])*dx+(p[2]-a[2])*dy)/length))
  return norm(p,interpolate(a,b,t)),t
end
function G.render_vertex(v)
  assert(type(v)=="table" and not (v.point and v.exact),"one authoritative coordinate representation required")
  if v.exact then return E.to_numbers(v.exact) end
  return point(v.point),{operation="identity-binary64",absolute_error_bounds={0,0}}
end
function G.intersect_exact_segments(a,b,c,d)
  for _,p in ipairs({a,b,c,d}) do E.validate_point(p,2) end
  local function equal(p,q) return E.compare(p.components[1],q.components[1])==0 and E.compare(p.components[2],q.components[2])==0 end
  local function between_exact(p,q,r)
    for i=1,2 do local l,u=q.components[i],r.components[i];if E.compare(l,u)>0 then l,u=u,l end;if E.compare(p.components[i],l)<0 or E.compare(p.components[i],u)>0 then return false end end
    return true
  end
  if equal(a,b) or equal(c,d) then return {kind="degenerate",reason="zero_length_exact_segment"} end
  local o1,o2,o3,o4=E.orient2d(a,b,c),E.orient2d(a,b,d),E.orient2d(c,d,a),E.orient2d(c,d,b)
  if o1==0 and o2==0 then
    local axis=E.compare(a.components[1],b.components[1])~=0 and 1 or 2
    local aa,bb=a,b;if E.compare(aa.components[axis],bb.components[axis])>0 then aa,bb=bb,aa end
    local cc,dd=c,d;if E.compare(cc.components[axis],dd.components[axis])>0 then cc,dd=dd,cc end
    local lo=E.compare(aa.components[axis],cc.components[axis])>=0 and aa or cc
    local hi=E.compare(bb.components[axis],dd.components[axis])<=0 and bb or dd
    if E.compare(lo.components[axis],hi.components[axis])>0 then return {kind="none",exact_classification=true} end
    if equal(lo,hi) then return {kind="point",classification="endpoint",exact=P.plain(lo),error_bound=0} end
    return {kind="overlap",from=P.plain(lo),to=P.plain(hi),exact_classification=true}
  end
  for _,v in ipairs({{o1,c,a,b},{o2,d,a,b},{o3,a,c,d},{o4,b,c,d}}) do if v[1]==0 and between_exact(v[2],v[3],v[4]) then return {kind="point",classification="endpoint",exact=P.plain(v[2]),error_bound=0} end end
  if o1*o2>=0 or o3*o4>=0 then return {kind="none",exact_classification=true} end
  local function delta(p,q) return {E.sub(p.components[1],q.components[1]),E.sub(p.components[2],q.components[2])} end
  local function cross(p,q) return E.sub(E.mul(p[1],q[2]),E.mul(p[2],q[1])) end
  local ab,cd,ac=delta(b,a),delta(d,c),delta(c,a);local t=E.div(cross(ac,cd),cross(ab,cd))
  local exact=E.point({E.add(a.components[1],E.mul(t,ab[1])),E.add(a.components[2],E.mul(t,ab[2]))})
  return {kind="point",classification="proper",exact=exact,parameter=t,error_bound=0,exact_classification=true}
end
local function ring_classify(r,p)
  local winding=0
  for i,a in ipairs(r) do
    local b=r[i%#r+1];local sign=N.orient2d(a,b,p)
    if sign==0 and between(p,a,b) then return "boundary" end
    if a[2]<=p[2] and b[2]>p[2] and sign>0 then winding=winding+1
    elseif a[2]>p[2] and b[2]<=p[2] and sign<0 then winding=winding-1 end
  end
  return winding~=0 and "inside" or "outside"
end
local function ring_edges(r,callback) for i,a in ipairs(r) do callback(a,r[i%#r+1],i) end end
local function check_ring(r,orientation,policy,charge)
  assert(type(r)=="table" and #r>=3 and #r<=2000,"ring needs 3..2000 open-list vertices")
  local out={};for i,p in ipairs(r) do out[i]=point(p) end
  for k in pairs(r) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=#r,"ring must be a dense vertex array") end
  assert(#out==#r,"sparse polygon ring")
  local lowest=1
  for i,p in ipairs(out) do
    assert(not same(p,out[i%#out+1]),"duplicate consecutive ring coordinate")
    if p[1]<out[lowest][1] or p[1]==out[lowest][1] and p[2]<out[lowest][2] then lowest=i end
    for j=i+1,#out do
      if j~=i+1 and not (i==1 and j==#out) then
        charge()
        local hit=G.segment_intersection(p,out[i%#out+1],out[j],out[j%#out+1],policy)
        assert(hit.kind=="none","self-intersecting/touching or degenerate polygon ring")
      end
    end
  end
  local sign=N.orient2d(out[(lowest-2)%#out+1],out[lowest],out[lowest%#out+1])
  assert(sign~=0,"collinear extreme ring corner; remove redundant collinear vertices explicitly")
  assert(sign==orientation,"outer must be counterclockwise and holes clockwise; explicit orientation repair required")
  return out
end
function G.region(outer,holes,policy,options)
  assert(type(holes)=="table","explicit hole array required");G.tolerance(policy)
  for k in pairs(holes) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=#holes,"holes must be a dense array") end
  for i=1,#holes do assert(holes[i]~=nil,"sparse hole array") end
  options=options or {};local pairs_checked=0;local limit=options.max_pair_checks or 100000
  for k in pairs(options) do assert(k=="context" or k=="max_pair_checks","unknown region construction option") end
  assert(type(limit)=="number" and limit%1==0 and limit>=0 and limit<=10000000,"invalid region pair-check budget")
  local function charge()pairs_checked=pairs_checked+1;assert(pairs_checked<=limit,"region pair-check budget exhausted");if options.context then options.context:consume("operations",1)end end
  local result={kind="polygon_region",schema_version=1,unit=policy.unit,fill_rule="evenodd",outer=check_ring(outer,1,policy,charge),holes=P.array()}
  local function disjoint(a,b)
    ring_edges(a,function(p,q)ring_edges(b,function(r,s)charge();assert(G.segment_intersection(p,q,r,s,policy).kind=="none","polygon rings touch or cross")end)end)
  end
  for _,h in ipairs(holes) do
    local hole=check_ring(h,-1,policy,charge);disjoint(result.outer,hole)
    assert(ring_classify(result.outer,hole[1])=="inside","hole outside outer ring")
    for _,other in ipairs(result.holes) do disjoint(other,hole);assert(ring_classify(other,hole[1])=="outside" and ring_classify(hole,other[1])=="outside","nested/overlapping holes need an explicit multipolygon representation") end
    result.holes[#result.holes+1]=hole
  end
  local region=P.snapshot(result);regions[region]=true;return region
end
function G.import_region(data,policy,options)
  data=P.plain(data)
  for k in pairs(data) do assert(k=="kind" or k=="schema_version" or k=="unit" or k=="fill_rule" or k=="outer" or k=="holes","unknown polygon region field") end
  assert(data.kind=="polygon_region" and data.schema_version==1 and data.unit==policy.unit and data.fill_rule=="evenodd","unsupported region schema/unit/fill rule")
  return G.region(data.outer,data.holes,policy,options)
end
function G.contains(region,p)
  assert(regions[region],"validated polygon region required; use import_region after deserialization")
  p=point(p);local status=ring_classify(region.outer,p)
  if status~="inside" then return status,"outer" end
  for i,h in ipairs(region.holes) do local s=ring_classify(h,p);if s=="boundary" then return s,"hole/"..i elseif s=="inside" then return "outside","hole/"..i end end
  return "inside"
end
function G.clip_segment(region,a,b,policy)
  assert(regions[region],"validated polygon region required; use import_region after deserialization")
  assert(region.unit==policy.unit,"clip unit mismatch");a,b=point(a),point(b)
  if same(a,b) then return {status="degenerate",reason="zero_length_segment"} end
  local breaks={0,1};local overlaps={};local contacts=P.array();local contact_map={};local collision=false;local tol=G.tolerance(policy,{a,b})
  local rings={region.outer};for _,h in ipairs(region.holes) do rings[#rings+1]=h end
  for ring_index,r in ipairs(rings) do ring_edges(r,function(c,d,edge_index)
    local hit=G.segment_intersection(a,b,c,d,policy)
    if hit.kind=="unresolved" then error("clip intersection exceeds numerical policy",0)
    elseif hit.kind=="point" then
      local t=math.max(0,math.min(1,hit.t));breaks[#breaks+1]=t
      if contact_map[t] then if hit.error_bound>0 or contact_map[t].error_bound>0 then collision=true end
      else local contact={parameter=t,point=hit.point,error_bound=hit.error_bound,ring=ring_index,edge=edge_index};contacts[#contacts+1]=contact;contact_map[t]=contact end
    elseif hit.kind=="overlap" then local t,u=G.parameter(hit.from,a,b),G.parameter(hit.to,a,b);breaks[#breaks+1]=t;breaks[#breaks+1]=u;overlaps[#overlaps+1]={math.min(t,u),math.max(t,u)} end
  end) end
  if collision then return {status="unresolved",reason="indistinguishable_clip_intersections",tolerance=tol} end
  table.sort(contacts,function(x,y)return x.parameter<y.parameter end)
  table.sort(breaks);local unique={};for _,v in ipairs(breaks) do if unique[#unique]~=v then unique[#unique+1]=v end end
  local segments=P.array()
  for i=2,#unique do
    local t,u=unique[i-1],unique[i];local middle=(t+u)/2;local p=interpolate(a,b,middle);local boundary=false
    for _,range in ipairs(overlaps) do if middle>=range[1] and middle<=range[2] then boundary=true end end
    local classification=boundary and "boundary" or G.contains(region,p)
    if not boundary then
      local distance=math.huge;for _,r in ipairs(rings) do ring_edges(r,function(c,d)local value=G.point_segment_distance(p,c,d);distance=math.min(distance,value)end) end
      if distance<=tol then return {status="unresolved",reason="clip_interval_within_boundary_tolerance",tolerance=tol,parameter_interval={t,u}} end
    end
    if classification=="inside" or boundary then segments[#segments+1]={from=interpolate(a,b,t),to=interpolate(a,b,u),parameters={t,u},classification=classification} end
  end
  return {status="complete",empty=#segments==0 and #contacts==0,segments=segments,contacts=contacts,tolerance=tol}
end
G.point=point
return G
