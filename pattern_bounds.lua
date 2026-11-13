local G,C,P=require("pattern_geometry"),require("pattern_curves"),require("pattern")
local B={VERSION="conservative-ink-v1"}
local function finite(n) assert(type(n)=="number" and n==n and math.abs(n)<math.huge,"finite bound required") end
local function box(b)
  assert(type(b)=="table" and #b==4,"[xmin,ymin,xmax,ymax] required");for _,v in ipairs(b) do finite(v) end
  for k in pairs(b) do assert(type(k)=="number" and k%1==0 and k>=1 and k<=4,"dense bounds tuple required") end
  assert(b[1]<=b[3] and b[2]<=b[4],"inverted bounds are not an empty region");return {b[1],b[2],b[3],b[4]}
end
local function include(a,b)
  if not a then return box(b) end
  return {math.min(a[1],b[1]),math.min(a[2],b[2]),math.max(a[3],b[3]),math.max(a[4],b[4])}
end
local function hypot(a,b) local m=math.max(math.abs(a),math.abs(b));return m==0 and 0 or m*math.sqrt((a/m)^2+(b/m)^2) end
function B.path(commands,paint,matrix,policy)
  assert(type(commands)=="table" and type(paint)=="table" and (paint.fill or paint.stroke),"path and actual paint required")
  matrix=matrix or {1,0,0,1,0,0};G.tolerance(policy)
  local current,start,geometry;local drawn=0
  for _,cmd in ipairs(commands) do
    local op=cmd[1]
    if op=="M" then assert(#cmd==3,"M arity");current=G.transform({cmd[2],cmd[3]},matrix);start=current
    elseif op=="L" then
      assert(current and #cmd==3,"L requires current point and endpoint");local p=G.transform({cmd[2],cmd[3]},matrix)
      geometry=include(geometry,{math.min(p[1],current[1]),math.min(p[2],current[2]),math.max(p[1],current[1]),math.max(p[2],current[2])});current=p;drawn=drawn+1
    elseif op=="C" then
      assert(current and #cmd==7,"C requires current point and three controls")
      local c={current,G.transform({cmd[2],cmd[3]},matrix),G.transform({cmd[4],cmd[5]},matrix),G.transform({cmd[6],cmd[7]},matrix)}
      geometry=include(geometry,C.tight_bounds(c,policy));current=c[4];drawn=drawn+1
    elseif op=="Z" then
      assert(current and start and #cmd==1,"Z requires an open subpath")
      geometry=include(geometry,{math.min(current[1],start[1]),math.min(current[2],start[2]),math.max(current[1],start[1]),math.max(current[2],start[2])});current=start;drawn=drawn+1
    else error("unsupported path command in bounds: "..tostring(op),0) end
  end
  if drawn==0 then return P.snapshot({empty=true,unit=policy.unit,reason="no_drawn_segments"}) end
  local padx,pady=0,0
  if paint.stroke then
    local width=paint.stroke_width;finite(width);assert(width>0,"positive stroke width required")
    local cap,join=paint.cap or "butt",paint.join or "miter"
    assert(cap=="butt" or cap=="round" or cap=="square","unsupported cap")
    assert(join=="miter" or join=="round" or join=="bevel","unsupported join")
    local factor=cap=="square" and math.sqrt(2) or 1
    if join=="miter" then local limit=paint.miter_limit or 10;finite(limit);assert(limit>=1,"miter limit must be at least1");factor=math.max(factor,limit) end
    local radius=width*factor/2
    padx,pady=radius*hypot(matrix[1],matrix[3]),radius*hypot(matrix[2],matrix[4])
  end
  local pad=G.tolerance(policy,{{geometry[1],geometry[2]},{geometry[3],geometry[4]}})
  local ink=box({geometry[1]-padx-pad,geometry[2]-pady-pad,geometry[3]+padx+pad,geometry[4]+pady+pad})
  return P.snapshot({empty=false,unit=policy.unit,geometry=geometry,bounds=ink,method="curve_extrema_plus_conservative_cap_join_affine_envelope",padding={padx+pad,pady+pad}})
end
function B.union(records,unit)
  assert(unit=="cm" or unit=="mm" or unit=="bp" or unit=="unit","explicit bounds unit required")
  local out
  for _,r in ipairs(records) do assert(r.unit==unit and type(r.empty)=="boolean","explicit matching-unit bounds record required");if not r.empty then out=include(out,r.bounds) end end
  return P.snapshot(out and {empty=false,unit=unit,bounds=out} or {empty=true,unit=unit,reason="empty_union"})
end
function B.intersects(a,b)
  a,b=box(a),box(b);return a[1]<=b[3] and a[3]>=b[1] and a[2]<=b[4] and a[4]>=b[2]
end
B.box=box
return B
