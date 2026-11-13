-- Filtered exact orientation for admitted binary64 inputs.
-- Independent Lua implementation of error-free arithmetic described by
-- Shewchuk, CMU-CS-96-140R (1997), sections 2.3--2.5 and 4.3.
local M={VERSION="orient2d-expansion-v1"}
local eps=2^-53
local function coordinate(n)
  assert(type(n)=="number" and n==n and math.abs(n)<=1e50 and (n==0 or math.abs(n)>=1e-50),"orientation coordinate outside admitted zero or 1e-50..1e50 range")
  return n+0.0
end
local function point(p) assert(type(p)=="table" and #p==2,"2D point required");return coordinate(p[1]),coordinate(p[2]) end
local function sum(a,b)
  local x=a+b;local bv=x-a;local av=x-bv
  return (a-av)+(b-bv),x
end
local function difference(a,b)
  local x=a-b;local bv=a-x;local av=x+bv
  return {(a-av)+(bv-b),x}
end
local function split(a)
  local c=134217729.0*a;local big=c-a;local hi=c-big
  return hi,a-hi
end
local function product(a,b)
  local x=a*b;local ah,al=split(a);local bh,bl=split(b)
  local e1=x-ah*bh;local e2=e1-al*bh;local e3=e2-ah*bl
  return al*bl-e3,x
end
local function grow(e,b)
  local out={};local q=b
  for _,a in ipairs(e) do local tail,head=sum(q,a);if tail~=0 then out[#out+1]=tail end;q=head end
  if q~=0 or #out==0 then out[#out+1]=q end
  return out
end
local function multiply(e,f)
  local out={0.0}
  for _,a in ipairs(e) do for _,b in ipairs(f) do local tail,head=product(a,b);out=grow(grow(out,tail),head) end end
  return out
end
local function sign(n) return n>0 and 1 or n<0 and -1 or 0 end
local function expansion(ax,ay,bx,by,cx,cy)
  local p=multiply(difference(ax,cx),difference(by,cy))
  local q=multiply(difference(ay,cy),difference(bx,cx))
  for _,v in ipairs(q) do p=grow(p,-v) end
  return p
end
function M.orient2d(a,b,c)
  local ax,ay=point(a);local bx,by=point(b);local cx,cy=point(c)
  local left=(ax-cx)*(by-cy);local right=(ay-cy)*(bx-cx);local det=left-right
  local bound=(3+16*eps)*eps*(math.abs(left)+math.abs(right))
  if math.abs(det)>bound then return sign(det),{method="filtered",approximate_determinant=det,error_bound=bound} end
  local p=expansion(ax,ay,bx,by,cx,cy)
  return sign(p[#p]),{method="exact_expansion",approximate_determinant=det,error_bound=bound,expansion=p}
end
function M.determinant_value(a,b,c)
  local ax,ay=point(a);local bx,by=point(b);local cx,cy=point(c)
  local p=expansion(ax,ay,bx,by,cx,cy);local estimate,magnitude=0.0,0.0
  for _,v in ipairs(p) do estimate=estimate+v;magnitude=magnitude+math.abs(v) end
  return estimate,2*eps*magnitude
end
function M.cubic_line_coefficients(controls,a,b)
  assert(type(controls)=="table" and #controls==4,"four cubic control points required")
  local ax,ay=point(a);local bx,by=point(b);local out={}
  for i,p in ipairs(controls) do local x,y=point(p);out[i]=expansion(ax,ay,bx,by,x,y) end
  return out
end
function M.expansion_sign(e) return sign(e[#e]) end
function M.expansion_half_add(e,f)
  local out={0.0};for _,v in ipairs(e) do out=grow(out,v*0.5) end;for _,v in ipairs(f) do out=grow(out,v*0.5) end
  return out
end
-- Exact equality is separate from geometric nearness and never assigns IDs.
function M.equal(a,b) local ax,ay=point(a);local bx,by=point(b);return ax==bx and ay==by end
return M
