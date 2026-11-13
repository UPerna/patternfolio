/* Dedicated worker: trusted Lua modules, bounded requests, no geometry in JS. */
'use strict';
let engine, session, job, inputBytes = 0;
const hashMeter = {calls: 0, bytes: 0, breached: false};
const CHUNK = 262144;
function send(type, payload = {}, transfers = []) {
  postMessage({schema_version: 1, type, request_id: job?.request_id ?? null,
    generation: job?.generation ?? null, ...payload}, transfers);
}
function luaString(value) {
  // Lua long literals discard an initial newline and normalize CR/LF.
  // Fixed-width decimal escapes preserve the exact UTF-8 source bytes,
  // including controls followed by digits, without changing source hashes.
  return '"' + value.replace(/[\x00-\x1f\x7f"\\]/g,
    character => '\\' + character.charCodeAt(0).toString(10).padStart(3, '0')) + '"';
}
function errorCode(message) {
  if (/memory|allocat/i.test(message)) return 'memory_budget';
  if (/budget|limit|too large/i.test(message)) return 'budget_exhausted';
  if (/solver|provider|offline|deadline/i.test(message)) return 'unsupported_solver_or_input';
  return 'invalid_input';
}
function validateEnvelope(data) {
  if (!data || data.schema_version !== 1 || !Number.isSafeInteger(data.request_id) || data.request_id < 1 ||
      !Number.isSafeInteger(data.generation) || data.generation < 1) throw Error('Invalid worker envelope');
}
self.onmessage = async event => {
  const data = event.data;
  try {
    validateEnvelope(data);
    if (data.type === 'init') {
      if (engine || job) throw Error('Worker already initialized');
      job = {request_id: data.request_id, generation: data.generation};
      if (!Number.isSafeInteger(data.memory_limit) || data.memory_limit < 2 * 1024 * 1024 || data.memory_limit > 256 * 1024 * 1024 ||
          !Number.isSafeInteger(data.instruction_limit) || data.instruction_limit < 1000 || data.instruction_limit > 32000000000 ||
          !Number.isSafeInteger(data.watchdog_ms) || data.watchdog_ms < 1 || data.watchdog_ms > 300000) throw Error('Invalid host budget configuration');
      job.instruction_limit = data.instruction_limit;
      const jsURL = URL.createObjectURL(new Blob([data.vendor], {type: 'text/javascript'}));
      try { importScripts(jsURL); } finally { URL.revokeObjectURL(jsURL); }
      const hashURL = URL.createObjectURL(new Blob([data.hash], {type: 'text/javascript'}));
      try { importScripts(hashURL); } finally { URL.revokeObjectURL(hashURL); }
      const wasmURL = URL.createObjectURL(new Blob([data.wasm], {type: 'application/wasm'}));
      try {
        const factory = new wasmoon.LuaFactory(wasmURL);
        engine = await factory.createEngine({traceAllocations: true, injectObjects: false, enableProxy: false});
      } finally { URL.revokeObjectURL(wasmURL); }
      engine.global.setMemoryMax(data.memory_limit);
      const sha = await hashwasm.createSHA256(), module = engine.global.lua.module, lengthPointer = module._malloc(4);
      engine.global.set('__browser_sha256', wasmoon.decorateFunction((thread, count) => {
        if (count !== 1 || thread.lua.lua_type(thread.address, 1) !== wasmoon.LuaType.String) throw Error('Hash input must be one byte string');
        const pointer = module._lua_tolstring(thread.address, 1, lengthPointer), length = module.getValue(lengthPointer, 'i32') >>> 0;
        hashMeter.calls++; hashMeter.bytes += length;
        if (length > 64 * 1024 * 1024 || hashMeter.bytes > 512 * 1024 * 1024 || hashMeter.calls > 1000000 || pointer + length > module.HEAPU8.length) {
          hashMeter.breached = true; throw Error('Browser host hash work budget exhausted');
        }
        return sha.init().update(module.HEAPU8.subarray(pointer, pointer + length)).digest('hex');
      }, {receiveThread: true, receiveArgsQuantity: true}));
      engine.global.set('__browser_observe', instructions => send('progress', {phase: 'shared-core', instructions, lua_memory_bytes: engine.global.getMemoryUsed()}));
      const hostIdentity = {user_agent: navigator.userAgent, instructions:data.instruction_limit, memory:data.memory_limit, watchdog_ms:data.watchdog_ms, hash_bytes:512*1024*1024, hash_calls:1000000};
      const hostDigest = sha.init().update(new TextEncoder().encode(JSON.stringify(hostIdentity))).digest('hex');
      job.host_identity = hostIdentity; job.host_digest = hostDigest;
      const source = data.bundle.source;
      if (!source || Object.keys(source).length > 128) throw Error('Source module budget');
      let program = 'local source={}\n';
      for (const [name, bytes] of Object.entries(source)) {
        if (!/^[A-Za-z0-9_-]+\.lua$/.test(name) || typeof bytes !== 'string') throw Error('Invalid source module');
        program += 'source[ ' + luaString(name) + ' ]=' + luaString(bytes) + '\n';
      }
      program += `
local trusted_load, hooks = load, debug.sethook
for name, bytes in pairs(source) do
  package.preload[name:sub(1,-5)] = assert(trusted_load(bytes,'@'..name,'t',_ENV))
end
package.searchers={function(name) local f=package.preload[name];return f or '\\n browser module unavailable:'..name end}
package.path='';package.cpath='';package.loadlib=nil;package.searchpath=nil
io=nil;os=nil;dofile=nil;loadfile=nil;load=nil;debug=nil
local Browser=require('pattern_browser')
local P=require('pattern')
local H=require('pattern_hash')
local ordinary_sha,hashing,hash_calls,hash_bytes=__browser_sha256,false,0,0
__browser_sha256=nil
H.sha256=function(bytes)
  assert(type(bytes)=='string'and #bytes<=64*1024*1024,'SHA-256 input must be bytes within64MiB')
  hash_calls=hash_calls+1;hash_bytes=hash_bytes+#bytes;hashing=true
  local ok,result=pcall(ordinary_sha,bytes);hashing=false
  if not ok then error(result,0)end
  return result
end
local observe=__browser_observe;__browser_observe=nil
local profile={instructions=0,hash_instructions=0}
function __browser_profile()return P.serialize({instructions=profile.instructions,hash_instructions=profile.hash_instructions,hash_calls=hash_calls,hash_bytes=hash_bytes})end
local state=Browser.session(source,${luaString(data.bundle.runtime + '|host-sha256:' + hostDigest)})
__browser_put=state.put
__browser_chunk=state.chunk
function __browser_run(header, maximum)
  local used, breached=0,false
  hooks(function()
    used=used+10000
    profile.instructions=used
    if hashing then profile.hash_instructions=profile.hash_instructions+10000 end
    if used%50000000==0 then observe(used)end
    if used>maximum then breached=true;hooks();error('browser deterministic instruction budget exhausted',0)end
  end,'',10000)
  local ok,result=pcall(state.dispatch,header)
  hooks()
  if breached then return P.serialize({ok=false,error={code='budget_exhausted',message='Deterministic Lua instruction budget exhausted'},instructions=used})end
  if not ok then return P.serialize({ok=false,error={code='invalid_input',message=tostring(result)},instructions=used})end
  return result,used
end
`;
      engine.doStringSync(program);
      send('ready', {runtime: data.bundle.runtime, lua_memory_bytes: engine.global.getMemoryUsed()});
      return;
    }
    if (!engine || !job || data.request_id !== job.request_id || data.generation !== job.generation) throw Error('Worker request identity mismatch');
    if (data.type === 'cancel') { send('cancelled'); close(); return; }
    if (data.type !== 'execute') throw Error('Unknown worker message type');
    const request = data.request;
    if (!request || !Array.isArray(request.input_files) || request.input_files.length > 1024) throw Error('Input object budget');
    if (!Array.isArray(data.files) || data.files.length > 1024 || data.files.length !== request.input_files.length) throw Error('Input file count');
    send('progress', {phase: 'inputs'});
    for (const file of data.files || []) {
      if (!file || typeof file.name !== 'string' || !(file.data instanceof ArrayBuffer)) throw Error('Invalid input file');
      inputBytes += file.data.byteLength;
      if (inputBytes > 32 * 1024 * 1024) throw Error('Input byte budget');
      const bytes = new Uint8Array(file.data);
      for (let at = 0; at < bytes.length; at += CHUNK) {
        let text = '';
        for (const value of bytes.subarray(at, at + CHUNK)) text += String.fromCharCode(value);
        engine.global.get('__browser_put')(file.name, btoa(text));
      }
      if (!bytes.length) engine.global.get('__browser_put')(file.name, '');
    }
    const maximum = data.instruction_limit ?? 16000000000;
    if (!Number.isSafeInteger(maximum) || maximum < 1000 || maximum > 32000000000) throw Error('Invalid instruction limit');
    if (maximum !== job.instruction_limit) throw Error('Instruction budget differs from initialized configuration');
    send('progress', {phase: 'shared-core'});
    engine.global.set('__browser_header', JSON.stringify(request));
    engine.global.set('__browser_maximum', maximum);
    const raw = engine.doStringSync('local result,used=__browser_run(__browser_header,__browser_maximum);__browser_used=used;return result');
    if (hashMeter.breached) { send('error', {error: {code: 'budget_exhausted', message: 'Host hash work budget exhausted'}, stats: hashMeter}); return; }
    const result = JSON.parse(raw);
    if (!result.ok) { send('error', {error: result.error, stats: JSON.parse(engine.doStringSync('return __browser_profile()'))}); return; }
    send('assets', {assets: result.assets, output_bytes: result.output_bytes});
    for (const asset of result.assets) {
      for (let at = 0; at < asset.bytes; at += CHUNK) {
        const encoded = engine.global.get('__browser_chunk')(asset.name, at, CHUNK);
        const decoded = atob(encoded), bytes = Uint8Array.from(decoded, value => value.charCodeAt(0));
        send('asset-chunk', {name: asset.name, offset: at, data: bytes.buffer}, [bytes.buffer]);
      }
    }
    send('complete', {instructions: engine.global.get('__browser_used'), lua_memory_bytes: engine.global.getMemoryUsed(), profile: JSON.parse(engine.doStringSync('return __browser_profile()')), host_identity: job.host_identity, host_digest: job.host_digest});
    engine.global.close();
    engine = null;
  } catch (error) {
    send('error', {error: {code: errorCode(String(error)), message: String(error)}});
  }
};
