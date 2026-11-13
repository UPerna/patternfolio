-- Cubic services and certified line-root isolation. General cubic/cubic
-- intersection remains an explicit unsupported operation, never an empty hit set.
local G,N,P=require("pattern_geometry"),require("pattern_predicates"),require("pattern")
local C={VERSION="cubic-bernstein-v1"};local eps=2^-52
local function controls(c)
  assert(type(c)=="table" and #c==4,"four cubic Bezier controls required")
  for k in pairs(c) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=4,"dense cubic control array required; weighted/rational curves are unsupported") end
  local out={};for i,p in ipairs(c) do out[i]=G.point(p) end;return out
end
local function lerp(a,b,t) return {(1-t)*a[1]+t*b[1],(1-t)*a[2]+t*b[2]} end
local function parameter(t) assert(type(t)=="number" and t>=0 and t<=1,"curve parameter must be in [0,1]") end
function C.evaluate(c,t)
  c=controls(c);parameter(t)
  if t==0 then return c[1] elseif t==1 then return c[4] end
  local a,b,d=lerp(c[1],c[2],t),lerp(c[2],c[3],t),lerp(c[3],c[4],t)
  return G.point(lerp(lerp(a,b,t),lerp(b,d,t),t))
end
function C.split(c,t)
  c=controls(c);parameter(t)
  local a,b,d=lerp(c[1],c[2],t),lerp(c[2],c[3],t),lerp(c[3],c[4],t)
  local e,f=lerp(a,b,t),lerp(b,d,t);local m=lerp(e,f,t)
  return {c[1],a,e,m},{m,f,d,c[4]}
end
function C.bounds(c,policy)
  c=controls(c);local out={c[1][1],c[1][2],c[1][1],c[1][2]}
  for _,p in ipairs(c) do out[1]=math.min(out[1],p[1]);out[2]=math.min(out[2],p[2]);out[3]=math.max(out[3],p[1]);out[4]=math.max(out[4],p[2]) end
  local pad=G.tolerance(policy,c)
  return {out[1]-pad,out[2]-pad,out[3]+pad,out[4]+pad},{method="convex_control_hull",absolute_padding=pad}
end
function C.tight_bounds(c,policy)
  c=controls(c);local points={c[1],c[4]};local fallback=false
  for axis=1,2 do
    local p,q,r,s=c[1][axis],c[2][axis],c[3][axis],c[4][axis]
    local a,b,d=-p+3*q-3*r+s,2*(p-2*q+r),q-p
    local scale=math.max(math.abs(a),math.abs(b),math.abs(d))
    if scale>0 then
      a,b,d=a/scale,b/scale,d/scale;local roots={}
      if a==0 then if b~=0 then roots[1]=-d/b end
      else
        local disc=b*b-4*a*d;local error=32*eps*(b*b+math.abs(4*a*d))
        if math.abs(disc)<=error then fallback=true
        elseif disc>0 then
          local v=-0.5*(b+(b>=0 and 1 or -1)*math.sqrt(disc));roots={v/a,d/v}
        end
      end
      for _,t in ipairs(roots) do if t>0 and t<1 then points[#points+1]=C.evaluate(c,t) end end
    end
  end
  if fallback then local box,receipt=C.bounds(c,policy);receipt.reason="near_multiple_extremum_uses_conservative_hull";return box,receipt end
  local box={points[1][1],points[1][2],points[1][1],points[1][2]}
  for _,p in ipairs(points) do box[1]=math.min(box[1],p[1]);box[2]=math.min(box[2],p[2]);box[3]=math.max(box[3],p[1]);box[4]=math.max(box[4],p[2]) end
  local pad=G.tolerance(policy,c)
  return {box[1]-pad,box[2]-pad,box[3]+pad,box[4]+pad},{method="analytic_derivative_extrema",absolute_padding=pad}
end
local function distance(a,b) return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2) end
local function coeff_split(f)
  local a,b,c=N.expansion_half_add(f[1],f[2]),N.expansion_half_add(f[2],f[3]),N.expansion_half_add(f[3],f[4])
  local d,e=N.expansion_half_add(a,b),N.expansion_half_add(b,c);local m=N.expansion_half_add(d,e)
  return {f[1],a,d,m},{m,e,c,f[4]}
end
function C.intersect_segment(c,a,b,policy,options)
  c=controls(c);a,b=G.point(a),G.point(b);options=options or {}
  for k in pairs(options) do assert(k=="max_depth" or k=="max_nodes","unknown curve query option") end
  assert(a[1]~=b[1] or a[2]~=b[2],"curve intersection requires nonzero segment")
  local tolerance=G.tolerance(policy,{c[1],c[2],c[3],c[4],a,b})
  local magnitude=policy.scale;local speed=0
  for i,p in ipairs(c) do magnitude=math.max(magnitude,math.abs(p[1]),math.abs(p[2]));if i>1 then speed=math.max(speed,3*distance(c[i-1],p)) end end
  if speed==0 then return {status="degenerate",reason="constant_curve",events=P.array(),tolerance=tolerance} end
  local paramtol=math.min(1,tolerance/(4*math.max(speed,tolerance)))
  local maxdepth=options.max_depth or 48;local budget=options.max_nodes or 10000
  assert(type(maxdepth)=="number" and type(budget)=="number" and maxdepth%1==0 and maxdepth>=1 and maxdepth<=48 and budget%1==0 and budget>=1 and budget<=1000000,"invalid curve root budget")
  local roots,unresolved={},P.array();local exact_roots={};local visited=0
  local function exact(t,multiplicity)
    if not exact_roots[t] then roots[#roots+1]={lo=t,hi=t,classification=multiplicity%2==0 and "tangent" or "crossing",multiplicity=multiplicity};exact_roots[t]=true end
  end
  local function visit(f,lo,hi,depth)
    visited=visited+1
    if visited>budget then unresolved[#unresolved+1]={interval={lo,hi},reason="root_node_budget"};return end
    local signs={};local changes,previous=0,nil;local nonzero=false
    for i,e in ipairs(f) do local s=N.expansion_sign(e);signs[i]=s;if s~=0 then nonzero=true;if previous and previous~=s then changes=changes+1 end;previous=s end end
    if not nonzero then unresolved[#unresolved+1]={interval={lo,hi},reason="coincident_curve_and_line"};return end
    if signs[1]==0 then local j=2;while signs[j]==0 do j=j+1 end;exact(lo,j-1) end
    if signs[4]==0 then local j=3;while signs[j]==0 do j=j-1 end;exact(hi,4-j) end
    if changes==0 then return end
    if changes==1 and signs[1]*signs[4]<0 and hi-lo<=paramtol then roots[#roots+1]={lo=lo,hi=hi,classification="crossing",multiplicity=1};return end
    if depth==maxdepth then unresolved[#unresolved+1]={interval={lo,hi},reason="near_tangent_or_multiple_root"};return end
    local left,right=coeff_split(f);local mid=(lo+hi)/2
    visit(left,lo,mid,depth+1);visit(right,mid,hi,depth+1)
  end
  visit(N.cubic_line_coefficients(c,a,b),0,1,0)
  table.sort(roots,function(x,y)return x.lo<y.lo end)
  local events=P.array();local previous
  for _,root in ipairs(roots) do
    if previous and root.lo<=previous.hi then unresolved[#unresolved+1]={interval={previous.lo,root.hi},reason="unseparated_roots"} end;previous=root
    local t=(root.lo+root.hi)/2;local p=C.evaluate(c,t);local u=G.parameter(p,a,b)
    local error=speed*(root.hi-root.lo)/2+16*eps*magnitude
    if root.lo==root.hi and (t==0 or t==1) then error=0 end
    local margin=error/distance(a,b)
    if u>=0 and u<=1 and (u>margin and u<1-margin or error==0) then
      events[#events+1]={point=p,curve_parameter=t,curve_interval={root.lo,root.hi},segment_parameter=u,classification=(t==0 or t==1) and "endpoint" or root.classification,multiplicity=root.multiplicity,error_bound=error}
    elseif u>=-margin and u<=1+margin then unresolved[#unresolved+1]={interval={root.lo,root.hi},reason="finite_segment_endpoint_precision"} end
  end
  return {status=#unresolved==0 and "complete" or "unresolved",empty=#events==0 and #unresolved==0,events=events,unresolved=unresolved,tolerance=tolerance,nodes=visited,method="exact_bernstein_sign_isolation"}
end
function C.intersect_cubics()
  error("general cubic/cubic intersection is unsupported; use certified cubic/segment queries or an explicitly validated solver",0)
end
return C
