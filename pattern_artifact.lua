-- Host-only immutable binary output, separate from portable byte serializers.
-- Visibility is atomic on the host filesystem; no power-loss durability claim.
local H=require("pattern_hash")
local M={}
local function read(path)local f=io.open(path,"rb");if not f then return nil end;local s=assert(f:read("*a"));assert(f:close());return s end
function M.write(path,bytes)
  assert(type(path)=="string" and type(bytes)=="string" and #bytes<=32*1024*1024,"bounded artifact bytes required")
  local lfs=require("lfs");local lock=path..".lock";assert(lfs.mkdir(lock),"artifact busy: "..path)
  local temp=path..".pending"
  local ok,result=pcall(function()
    local existing=read(path)
    if existing then assert(existing==bytes,"immutable artifact differs: "..path);return H.sha256(bytes)end
    assert(not read(temp),"unfinished artifact requires investigation: "..temp)
    local f=assert(io.open(temp,"wb"));assert(f:write(bytes));assert(f:close());assert(read(temp)==bytes,"artifact write verification failed")
    assert(not read(path),"artifact appeared during owned write");assert(os.rename(temp,path));assert(read(path)==bytes,"artifact publication verification failed")
    return H.sha256(bytes)
  end)
  assert(lfs.rmdir(lock),"artifact lock cleanup failed")
  assert(ok,result);return result
end
return M
