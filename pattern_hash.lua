-- SHA-256 from FIPS 180-4 sections 4.1.2, 4.2.2, 5.1.1, 5.3.3, 6.2.
-- Independent implementation; 32-bit words held in Lua 5.3 integers.
local P=require("pattern")
assert(math.maxinteger and math.maxinteger>=9007199254740991 and #string.pack("n",1)==8,"pattern hashes require Lua int64/binary64; runtime parity is an explicit gate")
local M={VERSION="sha256-frame-v1"}
local K={
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2}
local mask=0xffffffff
local function r(x,n) return ((x>>n)|(x<<(32-n)))&mask end
local function compute_sha256(bytes)
  assert(type(bytes)=="string" and #bytes<=64*1024*1024,"SHA-256 input must be bytes within 64 MiB")
  local len=#bytes;local bits=len*8
  bytes=bytes.."\128"..string.rep("\0",(55-len)%64)..string.pack(">I8",bits)
  local h={0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19}
  for pos=1,#bytes,64 do
    local w={};for i=1,16 do w[i]=string.unpack(">I4",bytes,pos+(i-1)*4) end
    for i=17,64 do
      local a,b=w[i-15],w[i-2]
      w[i]=(w[i-16]+(r(a,7)~r(a,18)~(a>>3))+w[i-7]+(r(b,17)~r(b,19)~(b>>10)))&mask
    end
    local a,b,c,d,e,f,g,j=table.unpack(h)
    for i=1,64 do
      local t1=(j+(r(e,6)~r(e,11)~r(e,25))+((e&f)~((~e)&g))+K[i]+w[i])&mask
      local t2=((r(a,2)~r(a,13)~r(a,22))+((a&b)~(a&c)~(b&c)))&mask
      j,g,f,e,d,c,b,a=g,f,e,(d+t1)&mask,c,b,a,(t1+t2)&mask
    end
    for i,v in ipairs({a,b,c,d,e,f,g,j}) do h[i]=(h[i]+v)&mask end
  end
  local out={};for i,v in ipairs(h) do out[i]=string.format("%08x",v) end;return table.concat(out)
end
-- Operational reuse only: Lua strings are immutable byte sequences. Keys are
-- the complete input bytes, never caller-owned tables, rounded coordinates or
-- an unverified supplied digest. This cache does not select pattern instances
-- or renderings. Its fixed limits include oversized-input bypass and FIFO
-- eviction; the original64MiB hashing contract and compression code are intact.
local CACHE_BYTES,CACHE_ENTRIES,CACHE_ENTRY=4*1024*1024,256,2*1024*1024
local cache,slots={},{}
local head,tail,count,held=1,1,0,0
local hits,misses,evictions,bypasses=0,0,0,0
local function evict()
  local bytes=slots[head];slots[head]=nil;head=head%CACHE_ENTRIES+1
  cache[bytes]=nil;count=count-1;held=held-#bytes;evictions=evictions+1
end
function M.sha256(bytes)
  assert(type(bytes)=='string'and #bytes<=64*1024*1024,'SHA-256 input must be bytes within 64 MiB')
  local value=cache[bytes]
  if value then hits=hits+1;return value end
  misses=misses+1;value=compute_sha256(bytes)
  if #bytes>CACHE_ENTRY then bypasses=bypasses+1;return value end
  while count>=CACHE_ENTRIES or held+#bytes>CACHE_BYTES do evict()end
  cache[bytes]=value;slots[tail]=bytes;tail=tail%CACHE_ENTRIES+1
  count=count+1;held=held+#bytes
  return value
end
-- Diagnostics/reset are for operational measurements. Never hash these
-- counters into recipes, instances, scenes or Build-record semantics. A host
-- SHA override (the pinned browser bridge) remains a separate implementation.
function M.sha256_cache_stats()
  return {implementation='pure-lua-sha256-byte-fifo-v1',entries=count,payload_bytes=held,
    maximum_entries=CACHE_ENTRIES,maximum_payload_bytes=CACHE_BYTES,maximum_entry_bytes=CACHE_ENTRY,
    hits=hits,misses=misses,evictions=evictions,oversized_bypasses=bypasses}
end
function M.clear_sha256_cache()
  cache,slots={},{};head,tail,count,held=1,1,0,0;hits,misses,evictions,bypasses=0,0,0,0
end
local function frame(s) return tostring(#s)..":"..s end
function M.bytes(domain,bytes)
  assert(type(domain)=="string" and #domain>0 and type(bytes)=="string","hash domain and bytes required")
  return M.sha256("pattern-platform\0hash-v1\0"..frame(domain)..frame(bytes))
end
function M.value(domain,value) return M.bytes(domain,P.serialize(value)) end
function M.is_digest(s) return type(s)=="string" and #s==64 and not s:find("[^0-9a-f]") end
return M
