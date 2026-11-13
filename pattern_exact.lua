-- Bounded reduced rational coordinates. Overflow/complexity is a diagnostic,
-- never a silent conversion to floating-point construction coordinates.
local M={VERSION="rational-26-v1",MAX_COMPONENT=67108864}
local safe=9007199254740991
local function integer(n)
  assert(type(n)=="number" and n==n and n%1==0 and n>=-safe and n<=safe,"exact rational integer outside safe range")
  return assert(math.tointeger(n))
end
local function gcd(a,b) a,b=math.abs(a),math.abs(b);while b~=0 do a,b=b,a%b end;return a end
function M.new(n,d)
  n,d=integer(n),integer(d or 1);assert(d~=0,"zero rational denominator")
  if d<0 then n,d=-n,-d end
  local g=gcd(n,d);n,d=n//g,d//g
  assert(math.abs(n)<=M.MAX_COMPONENT and d<=M.MAX_COMPONENT,"rational coordinate complexity budget exceeded")
  return {n,d}
end
function M.validate(r)
  assert(type(r)=="table" and #r==2,"rational [numerator,denominator] required")
  for k in pairs(r) do assert(k==1 or k==2,"unknown rational key") end
  local v=M.new(r[1],r[2]);assert(v[1]==r[1] and v[2]==r[2],"rational must be reduced with positive denominator")
  return v
end
function M.add(a,b) a,b=M.validate(a),M.validate(b);return M.new(a[1]*b[2]+b[1]*a[2],a[2]*b[2]) end
function M.neg(a) a=M.validate(a);return {-a[1],a[2]} end
function M.sub(a,b) return M.add(a,M.neg(b)) end
function M.mul(a,b)
  a,b=M.validate(a),M.validate(b)
  local g,h=gcd(a[1],b[2]),gcd(b[1],a[2])
  return M.new((a[1]//g)*(b[1]//h),(a[2]//h)*(b[2]//g))
end
function M.div(a,b) b=M.validate(b);assert(b[1]~=0,"rational division by zero");return M.mul(a,M.new(b[2],b[1])) end
function M.compare(a,b) a,b=M.validate(a),M.validate(b);local v=a[1]*b[2]-b[1]*a[2];return v>0 and 1 or v<0 and -1 or 0 end
function M.point(components)
  assert(type(components)=="table" and (#components==2 or #components==3),"exact point dimension must be 2 or 3")
  for k in pairs(components) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=#components,"dense exact coordinate array required") end
  for i=1,#components do assert(components[i]~=nil,"sparse exact coordinate array") end
  local out={coordinate_type="rational",components={}}
  for i,r in ipairs(components) do out.components[i]=M.validate(r) end
  return out
end
function M.validate_point(p,dimension)
  assert(type(p)=="table" and p.coordinate_type=="rational" and type(p.components)=="table" and #p.components==dimension,"rational exact point with matching dimension required")
  for k in pairs(p) do assert(k=="coordinate_type" or k=="components","unknown exact coordinate field") end
  for k,r in pairs(p.components) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=dimension,"dense exact coordinate components required");M.validate(r) end
  for i=1,dimension do assert(p.components[i]~=nil,"sparse exact coordinate components") end
  return true
end
function M.to_numbers(p)
  M.validate_point(p,#p.components);local out={};local errors={}
  for i,r in ipairs(p.components) do out[i]=r[1]/r[2];errors[i]=math.abs(out[i])*2^-52 end
  return out,{operation="rational-to-binary64-v1",absolute_error_bounds=errors}
end
function M.orient2d(a,b,c)
  for _,p in ipairs({a,b,c}) do M.validate_point(p,2) end
  local ax=M.sub(a.components[1],c.components[1]);local ay=M.sub(a.components[2],c.components[2])
  local bx=M.sub(b.components[1],c.components[1]);local by=M.sub(b.components[2],c.components[2])
  return M.compare(M.mul(ax,by),M.mul(ay,bx))
end
return M
