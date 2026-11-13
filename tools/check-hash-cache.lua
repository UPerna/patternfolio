-- Check real default hash implementation and bounded byte reuse, never a host override.
local P,H,Parse=require('pattern'),require('pattern_hash'),require('pattern_parse')
local fs=require('lfs');local f=assert(io.open('docs/validation/fixtures/hash-cache-v1.json','rb'));local fixture=Parse.decode(f:read('*a'));f:close()
local count=0;local function check(ok,why)assert(ok,why);count=count+1 end
local function payload(v)
 if v.text then return v.text end
 if v.kind=='all-bytes'then local a={};for i=0,255 do a[#a+1]=string.char(i)end;return table.concat(a):rep(v.repetitions)end
 return string.rep(string.char(v.byte),v.length-8)..string.format('%08d',v.id)
end
H.clear_sha256_cache();local stats=H.sha256_cache_stats();check(stats.entries==0 and stats.payload_bytes==0,'cache reset')
for _,v in ipairs(fixture.vectors)do
 local bytes=payload(v);local before=H.sha256_cache_stats();local digest=H.sha256(bytes)
 check(digest==v.sha256,'Independent hashlib vector:'..v.name)
 check(H.sha256(bytes)==v.sha256,'Repeat changed SHA:'..v.name)
 local after=H.sha256_cache_stats()
 if #bytes<=after.maximum_entry_bytes then check(after.hits>before.hits,'Exact immutable bytes did not reuse verified SHA')
 else check(after.oversized_bypasses>=before.oversized_bypasses+2 and after.entries==before.entries,'Oversized SHA entered cache')end
 check(after.payload_bytes<=after.maximum_payload_bytes and after.entries<=after.maximum_entries,'Hash cache exceeded resource contract')
end
H.clear_sha256_cache()
for i=1,600 do
 local bytes='distinct-entry-'..i;local a=H.sha256(bytes)
 check(type(a)=='string'and #a==64,'Missing digest under entry pressure')
 local s=H.sha256_cache_stats();check(s.entries<=256 and s.payload_bytes<=4*1024*1024,'Entry pressure exceeded bound')
end
check(H.sha256_cache_stats().evictions>=344,'Entry eviction did not occur')
H.clear_sha256_cache()
for _,v in ipairs(fixture.memory_pressure)do
 check(H.sha256(payload(v))==v.sha256,'Byte-pressure vector mismatch')
 local s=H.sha256_cache_stats();check(s.payload_bytes<=4*1024*1024 and s.entries<=256,'Byte pressure exceeded bound')
end
check(H.sha256_cache_stats().evictions>0,'Byte eviction did not occur')
local oldest=fixture.memory_pressure[1];local before=H.sha256_cache_stats()
check(H.sha256(payload(oldest))==oldest.sha256 and H.sha256_cache_stats().misses>before.misses,'Evicted value was not safely recomputed')
local invalid_before=H.sha256_cache_stats()
for _,bad in ipairs{false,1,{}}do check(not pcall(H.sha256,bad),'Non-byte input entered SHA cache')end
check(H.sha256_cache_stats().entries==invalid_before.entries,'Invalid input mutated cache')
local t={number=1,text='retained'};local original=H.value('cache-mutation-control',t);t.number=2
check(H.value('cache-mutation-control',t)~=original,'Caller-owned table mutation reused stale hash')
t.number=1;check(H.value('cache-mutation-control',t)==original,'Canonical original bytes changed')
local warm=H.sha256_cache_stats();H.clear_sha256_cache()
for _,v in ipairs(fixture.vectors)do check(H.sha256(payload(v))==v.sha256,'Cold and warm hash disagreement')end
local source={}
for _,name in ipairs{'pattern_hash.lua','pattern.lua','pattern_json.lua','tools/check-hash-cache.lua','docs/validation/fixtures/hash-cache-v1.json'}do
 local f=assert(io.open(name,'rb'));source[name]=H.sha256(f:read('*a'));f:close()
end
fs.mkdir('build');fs.mkdir('build/hash-cache')
local receipt={status='passed',actual_lua=_VERSION,checks=count,fixture_version=fixture.schema_version,source_files=source,source_digest=H.value('hash-cache/test-source',source),
 vectors=#fixture.vectors,memory_pressure_vectors=#fixture.memory_pressure,warm_stats=warm,final_stats=H.sha256_cache_stats(),
 input_guard_bytes=64*1024*1024,caller_table_mutation_detected=true,semantic_cold_warm_equal=true,
 scope='Actual shared pure-Lua SHA compression and exact immutable-byte FIFO cache; browser host-SHA override separately retained/tested'}
local out=assert(io.open('build/hash-cache/receipt-'.._VERSION:gsub(' ','-')..'.json','wb'));out:write(P.serialize(receipt));out:close();print('Bounded SHA cache checks',count,_VERSION);return receipt
