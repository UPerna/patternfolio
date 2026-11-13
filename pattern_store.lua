-- Immutable cache files. Lock directory and temporary bytes share destination volume.
-- Host adapters must provide atomic mkdir and same-volume rename; no unsafe fallback.
local H,P=require("pattern_hash"),require("pattern")
local M={}
function M.new(directory,host)
  assert(type(directory)=="string" and #directory>0,"cache directory required")
  if not host then local lfs=require("lfs");host={mkdir=lfs.mkdir,rmdir=lfs.rmdir,rename=os.rename,remove=os.remove,open=io.open} end
  for _,k in ipairs({"mkdir","rmdir","rename","remove","open"}) do assert(type(host[k])=="function","atomic store host lacks "..k) end
  local function filename(key) assert(H.is_digest(key),"cache key must be SHA-256");return directory.."/"..key..".json" end
  local store={}
  function store:get(key)
    local file,err,errno=host.open(filename(key),"rb");if not file then return nil,errno==2 and "missing" or "unreadable cache entry: "..tostring(err) end
    local bytes=file:read(2*1024*1024+1);file:close()
    if #bytes>2*1024*1024 then return nil,"oversized cache entry" end
    local ok,entry=pcall(require("pattern_parse").decode,bytes)
    if not ok or type(entry)~="table" or entry.kind~="cache_entry" or entry.schema_version~=1 or entry.key~=key or type(entry.payload)~="string" or not H.is_digest(entry.sha256) or H.sha256(entry.payload)~=entry.sha256 then
      return nil,"invalid or incomplete cache entry"
    end
    return entry.payload
  end
  function store:put(key,payload)
    assert(type(payload)=="string" and #payload<=1024*1024,"cache payload must be UTF-8 data within 1 MiB")
    local final=filename(key);local lock=final..".lock";local temp=lock.."/payload.tmp"
    local acquired,why=host.mkdir(lock);if not acquired then return nil,"cache writer busy or stale lock: "..tostring(why) end
    local ok,result=pcall(function()
      local existing,reason=self:get(key)
      if existing then assert(existing==payload,"cache key collision or nondeterministic output");return true end
      assert(reason=="missing","existing cache entry is corrupt; explicit quarantine required")
      local entry=P.serialize({kind="cache_entry",schema_version=1,key=key,sha256=H.sha256(payload),payload=payload})
      assert(#entry<=2*1024*1024,"escaped cache entry exceeds 2 MiB")
      local f=assert(host.open(temp,"wb"));local wrote,err=f:write(entry);local flushed,fe=f:flush();local closed,ce=f:close()
      assert(wrote and flushed and closed,err or fe or ce or "cache write failed")
      local check=assert(host.open(temp,"rb"));local actual=check:read("*a");check:close();assert(actual==entry,"cache write verification failed")
      assert(host.rename(temp,final));return true
    end)
    host.remove(temp);local removed,cleanup=host.rmdir(lock)
    if not ok then return nil,tostring(result) end
    if not removed then return nil,"cache published but lock cleanup failed: "..tostring(cleanup) end
    return result
  end
  return store
end
return M
