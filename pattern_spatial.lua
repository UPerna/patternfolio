-- Deterministic bounded AABB sweep index; IDs never come from coordinates.
local P,B=require("pattern"),require("pattern_bounds")
local S={VERSION="aabb-sweep-v1"}
function S.new(max_objects)
  max_objects=max_objects or 10000;assert(type(max_objects)=="number" and max_objects%1==0 and max_objects>=1 and max_objects<=100000,"invalid index object budget")
  local objects,ids={},{};local dirty=false;local index={}
  function index:insert(id,bounds)
    assert(type(id)=="string" and #id>0 and not ids[id],"unique semantic index ID required")
    P.snapshot(id)
    assert(#objects<max_objects,"spatial index budget exhausted")
    local b=B.box(bounds);objects[#objects+1]={id=id,bounds=b};ids[id]=true;dirty=true
  end
  function index:query(bounds)
    local b=B.box(bounds)
    if dirty then table.sort(objects,function(a,c)return a.bounds[1]<c.bounds[1] or a.bounds[1]==c.bounds[1] and P.byte_less(a.id,c.id) end);dirty=false end
    local result=P.array();local examined=0
    for _,v in ipairs(objects) do
      if v.bounds[1]>b[3] then break end;examined=examined+1
      if B.intersects(v.bounds,b) then result[#result+1]=v.id end
    end
    table.sort(result,P.byte_less);return P.snapshot(result),{method=S.VERSION,examined=examined,total=#objects}
  end
  return index
end
return S
