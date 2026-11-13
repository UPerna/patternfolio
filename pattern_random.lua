-- Park/Miller 1988, Schrage arithmetic; isolated versioned semantic streams.
local H,P=require("pattern_hash"),require("pattern")
local M={VERSION="pm16807-schrage-v1"}
function M.new(seed)
  assert(type(seed)=="number" and seed%1==0 and seed>=1 and seed<=2147483646,"PRNG seed must be 1..2147483646")
  local state=seed;local r={}
  function r.next_integer()
    local hi=math.floor(state/127773);local lo=state-hi*127773
    local t=16807*lo-2836*hi;state=t>0 and t or t+2147483647;return state
  end
  function r.u() return r.next_integer()/2147483647 end
  function r.range(a,b) assert(type(a)=="number" and type(b)=="number" and a<=b and a>-math.huge and b<math.huge and b-a<math.huge,"invalid range");return a+(b-a)*r.u() end
  function r.int(a,b)
    assert(type(a)=="number" and type(b)=="number" and a%1==0 and b%1==0 and a>=-9007199254740991 and b<=9007199254740991 and a<=b and b-a<2147483646,"invalid integer range")
    local span=b-a+1;local limit=2147483646-(2147483646%span);local n
    repeat n=r.next_integer()-1 until n<limit
    return a+n%span
  end
  function r.save() return state end
  return r
end
function M.seed(root,namespace,name,semantic_id)
  assert(type(root)=="number" and root%1==0 and root>=0 and root<2^31,"invalid root seed")
  for i=1,3 do local s=select(i,namespace,name,semantic_id);assert(type(s)=="string" and #s>0,"named semantic identity required") end
  local digest=H.value("random/"..M.VERSION,{seed=root,namespace=namespace,name=name,semantic_id=semantic_id})
  return tonumber(digest:sub(1,8),16)%2147483646+1
end
function M.provider(root,namespace)
  local streams={}
  return function(name,id,seed)
    assert(seed==root,"stream provider root seed mismatch")
    local key=P.serialize({name,id})
    if not streams[key] then streams[key]=M.new(M.seed(root,namespace,name,id)) end
    return streams[key]
  end
end
return M
