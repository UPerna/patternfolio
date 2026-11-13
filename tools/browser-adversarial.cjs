/* Controlled failure injection in a real browser, alongside actual worker executions. */
const fs = require('node:fs'), path = require('node:path'), crypto = require('node:crypto');
const args = Object.fromEntries(process.argv.slice(2).map((v,i,a)=>v.startsWith('--')?[v.slice(2),a[i+1]]:null).filter(Boolean));
const pw = require(args.playwright || 'playwright');
async function main() {
 const browser = await pw.chromium.launch({headless:true,...(args.executable?{executablePath:args.executable}:{})});
 const context = await browser.newContext(), page = await context.newPage();
 try {
  await page.goto(args.url || 'http://127.0.0.1:8767/');
  await page.evaluate(()=>runtimeReady);
  const lengths=[0,1,2,3,54,55,56,57,63,64,65,66,119,120,127,128,129,255,256,257,65535,65536,65537,1000000];
  const vectors=lengths.map(n=>{const bytes=Buffer.from(Array.from({length:n},(_,i)=>i%256));return {bytes:n,sha256:crypto.createHash('sha256').update(bytes).digest('hex')}});
  const probe="local H,P,R=require('pattern_hash'),require('pattern'),require('pattern_random');assert(tostring(math.maxinteger)=='9223372036854775807'and #string.pack('n',1)==8,'int64/binary64');local raw='';for i=0,255 do raw=raw..string.char(i)end;"+vectors.map(v=>"assert(H.sha256(raw:rep("+Math.floor(v.bytes/256)+")..raw:sub(1,"+(v.bytes%256)+"))=='"+v.sha256+"','binary SHA vector "+v.bytes+"');").join('')+"local r=R.new(1);for _,n in ipairs{16807,282475249,1622650073,984943658,1144108930,470211272,101027544,1457850878,1458777923,2007237709}do assert(r.next_integer()==n,'PRNG vector')end;assert(P.serialize({unicode='Ω',number=0.1,integer=9007199254740991})==[=[{\"integer\":9007199254740991,\"number\":0.10000000000000001,\"unicode\":\"Ω\"}]=],'canonical numeric/Unicode vector');";
  const nativeMicro=args['native-micrography']?fs.readFileSync(args['native-micrography'],'utf8'):null;
  const receipt = await page.evaluate(async({probe,vectors,nativeMicro})=>{
   const {PatternWorkerClient,ImmutableResultCache} = await import('./client.js');
   const {sha256} = await import('./cache.js');
   const loaded = await runtimeReady, reports=[];
   const assert=(ok,why)=>{if(!ok)throw Error(why)};
   async function check(name,fn){const started=performance.now();const evidence=await fn();reports.push({name,status:'passed',elapsed_ms:performance.now()-started,evidence});}
   async function rejects(promise,code){try{await promise}catch(e){assert(!code||e.code===code,'Expected '+code+', got '+e.code+': '+e.message);return {code:e.code??null,message:e.message}}throw Error('Failure accepted as success');}
   const periodic={command:'generate',files:{'recipe.json':loaded.bundle.examples['periodic.recipe']}};
   await check('capabilities',async()=>{
    const r=await patternClient.execute({command:'capabilities'}),v=JSON.parse(new TextDecoder().decode(r.assets['report.json']));
    assert(v.commands.length===8 && /native-process solvers are unavailable/.test(v.optional_providers),'Missing feature boundaries');
    window.__capabilityResult=r; return {commands:v.commands,optional_providers:v.optional_providers,stats:r.stats};
   });
   await check('production-host-sha-prng-canonical-conformance',async()=>{
    // Trusted test instrumentation enters at session construction, after the
    // production worker installs its actual raw-byte SHA callback. No user Lua.
    const client=new PatternWorkerClient('./');const instrumented=structuredClone(loaded.bundle);
    const original=instrumented.source['pattern_browser.lua'];
    instrumented.source['pattern_browser.lua']=original.replace('function M.session(source,runtime)','function M.session(source,runtime)\n'+probe+'\n');
    client.load=async()=>({...loaded,bundle:instrumented});
    const result=await client.execute({command:'capabilities'});
    assert(result.manifest.length>0,'Primitive conformance did not complete');
    return {trusted_test_instrumentation:true,actual_production_worker_sha_callback:true,binary_vectors:vectors,prng_values:10,canonical_numeric_utf8:true,stats:result.stats};
   });
   await check('client-invalid-command',()=>rejects(patternClient.execute({command:'shell'}),'invalid_input'));
   if(nativeMicro)await check('actual-native-micrography-cross-runtime-structural-validation',async()=>{
    const client=new PatternWorkerClient('./'), instrumented=structuredClone(loaded.bundle);
    // Trusted fixture enters at the real family-validation API, without forging
    // a browser build record or changing the native instance bytes.
    const quote=value=>'"'+value.replace(/[\x00-\x1f\x7f"\\]/g,c=>'\\'+c.charCodeAt(0).toString(10).padStart(3,'0'))+'"';
    instrumented.source['stage33_native_micro.lua']=`return function()
local P,R,C,Parse=require('pattern'),require('pattern_registry'),require('pattern_cli_core'),require('pattern_parse')
local x=Parse.instance(${quote(nativeMicro)})
local reg=C.registry('text/digital-micrography')
local function ctx()return R.context({source={revision='native-fixture-cross-runtime'},seed=x.provenance.seed,frame=x.frame,limits={objects=100000,operations=48000000,bytes=67108864}})end
reg:validate('text/digital-micrography',x,ctx())
for _,mutate in ipairs{
function(a)a.extensions.micrography.positions[1].line=1-2^-53 end,
function(a)a.extensions.micrography.field.triangles[1][1]=999999 end,
function(a)local v=a.extensions.micrography.field.labels.samples[1];v.label=1-v.label end
}do local bad=P.plain(x);mutate(bad);assert(not pcall(reg.validate,reg,'text/digital-micrography',bad,ctx()),'native fixture corruption accepted')end
reg:validate('text/digital-micrography',x,ctx())
end`;
    const marker='function M.session(source,runtime)';assert(instrumented.source['pattern_browser.lua'].includes(marker),'Native session instrumentation marker missing');
    instrumented.source['pattern_browser.lua']=instrumented.source['pattern_browser.lua'].replace(marker,marker+"\nrequire('stage33_native_micro')()\n");
    client.load=async()=>({...loaded,bundle:instrumented});
    const result=await client.execute({command:'capabilities'});assert(result.manifest.length>0,'Cross-runtime validation incomplete');
    return {native_instance_sha256:await sha256(new TextEncoder().encode(nativeMicro)),production_worker:true,actual_family_validator:true,controlled_corruptions_detected:3,original_preserved:true,scope:'Native instance structural validation; no forged browser build record or cross-version build-record replay claim'};
   });
   await check('raw-module-transport-leading-newline-crlf-controls',async()=>{
    const client=new PatternWorkerClient('./'), instrumented=structuredClone(loaded.bundle);
    // Change trusted test inputs, never their expected hashes after transport.
    // Capabilities constructs a real shared-core session in the production worker.
    for(const name of Object.keys(instrumented.source))
      instrumented.source[name]='\n'+instrumented.source[name].replace(/\r?\n/g,'\r\n');
    instrumented.source['stage33_transport.lua']='\n-- delimiters ]=] ]==] " \\ Ω\r\nreturn "transport\\0009\\013\\010"\r';
    const marker='function M.session(source,runtime)';
    assert(instrumented.source['pattern_browser.lua'].includes(marker),'Session instrumentation marker missing');
    const transportNames=Object.keys(instrumented.source).filter(name=>name!=='pattern_browser.lua');
    let assertions="\nlocal hash=require('pattern_hash');";
    for(const name of transportNames){
      const expected=await sha256(new TextEncoder().encode(instrumented.source[name]));
      assertions+="assert(hash.sha256(source['"+name+"'])=='"+expected+"','raw-source-sha:"+name+"');";
    }
    assertions+="assert(require('stage33_transport')=='transport'..string.char(0)..'9'..string.char(13,10),'control literal semantics');\n";
    instrumented.source['pattern_browser.lua']=instrumented.source['pattern_browser.lua'].replace(marker,marker+assertions);
    client.load=async()=>({...loaded,bundle:instrumented});
    const result=await client.execute({command:'capabilities'});
    assert(result.manifest.length>0,'Raw source transport execution incomplete');
    return {production_worker:true,raw_source_sha256_checks:transportNames.length,leading_newline:true,crlf:true,literal_carriage_return:true,delimiter_quote_backslash_unicode:true,embedded_nul_followed_by_digit:true};
   });
   await check('client-unknown-field',()=>rejects(patternClient.execute({command:'capabilities',script:'evil'}),'invalid_input'));
   await check('client-invalid-filename',()=>rejects(patternClient.execute({command:'generate',files:{'../escape':'x'}}),'invalid_input'));
   await check('client-input-bytes',()=>rejects(patternClient.execute({command:'generate',files:{'recipe.json':new Uint8Array(32*1024*1024+1)}}),'budget_exhausted'));
   await check('client-input-file-count',()=>rejects(patternClient.execute({command:'generate',files:Object.fromEntries(Array.from({length:1025},(_,i)=>['f'+i,'']))}),'budget_exhausted'));
   await check('client-depth',()=>{let o={};for(let i=0;i<65;i++)o={n:o};return rejects(patternClient.execute({command:'capabilities',dependencies:o}),'budget_exhausted')});
   await check('client-object-count',()=>rejects(patternClient.execute({command:'capabilities',dependencies:Array(100001).fill(1)}),'budget_exhausted'));
   await check('client-cycle',()=>{let o={};o.self=o;return rejects(patternClient.execute({command:'capabilities',dependencies:o}),'invalid_input')});
   await check('client-host-limits',()=>rejects(patternClient.execute(periodic,{instructionLimit:Infinity}),'invalid_input'));
   await check('actual-worker-malformed-recipe',()=>rejects(patternClient.execute({command:'generate',files:{'recipe.json':'{"broken":'}})));
   await check('actual-worker-instruction-limit',()=>rejects(patternClient.execute(periodic,{instructionLimit:1000}),'budget_exhausted'));
   await check('actual-worker-memory-limit',()=>rejects(patternClient.execute(periodic,{memoryLimitBytes:2*1024*1024}),'memory_budget'));
   await check('actual-worker-watchdog',()=>rejects(patternClient.execute(periodic,{watchdogMs:1}),'timeout'));
   await check('actual-worker-object-budget',()=>rejects(patternClient.execute({...periodic,limits:{objects:1,operations:48000000,bytes:67108864}})));
   await check('actual-worker-budget-above-cap',()=>rejects(patternClient.execute({...periodic,limits:{objects:100001,operations:48000000,bytes:67108864}}),'invalid_input'));
   await check('actual-worker-cancel-during-core',async()=>{
    let cancelled=false;
    const p=patternClient.execute(periodic,{progress:v=>{if(v.phase==='shared-core'&&!cancelled){cancelled=true;patternClient.cancel()}}});
    const e=await rejects(p,'cancelled');assert(cancelled&&!patternClient.pending,'Worker cancellation failed');return e;
   });
   await check('actual-worker-supersede',async()=>{
    const first=patternClient.execute(periodic).then(()=>{throw Error('Old generation completed')},e=>e.code);
    const second=await patternClient.execute({command:'capabilities'});
    assert(await first==='superseded' && second.generation===patternClient.generation,'Stale generation won');return {generation:second.generation};
   });
   async function rawWorker(message,initialize=false){
    const u=URL.createObjectURL(new Blob([loaded.worker],{type:'text/javascript'})),w=new Worker(u);
    try{return await new Promise((resolve,reject)=>{
     const timer=setTimeout(()=>reject(Error('Raw worker test timeout')),15000);
     w.onmessage=e=>{if(e.data.type==='progress')return;if(e.data.type==='ready'){w.postMessage(message);return}if(e.data.type==='error'){clearTimeout(timer);resolve(e.data)}else{clearTimeout(timer);reject(Error('Unexpected raw worker success '+e.data.type))}};
     w.onerror=e=>{clearTimeout(timer);reject(Error(e.message))};
     if(initialize)w.postMessage({schema_version:1,type:'init',request_id:1,generation:1,bundle:loaded.bundle,vendor:loaded.vendor,hash:loaded.hash,wasm:loaded.wasm,instruction_limit:16000000000,memory_limit:268435456,watchdog_ms:300000});else w.postMessage(message);
    })}finally{w.terminate();URL.revokeObjectURL(u)}
   }
   await check('actual-worker-protocol-version',()=>rawWorker({schema_version:99,type:'execute',request_id:1,generation:1}));
   await check('actual-worker-request-identity',()=>rawWorker({schema_version:1,type:'execute',request_id:2,generation:1},true));
   await check('actual-worker-unknown-message',()=>rawWorker({schema_version:1,type:'unknown',request_id:1,generation:1},true));
   await check('actual-worker-file-count-mismatch',()=>rawWorker({schema_version:1,type:'execute',request_id:1,generation:1,request:{input_files:[]},files:[{name:'x',data:new ArrayBuffer(1)}]},true));
   await check('actual-worker-input-digest',()=>rawWorker({schema_version:1,type:'execute',request_id:1,generation:1,request:{schema_version:1,command:'capabilities',input_files:[{name:'x',bytes:1,sha256:'0'.repeat(64)}]},files:[{name:'x',data:new Uint8Array([1]).buffer}],instruction_limit:16000000000},true));
   const RealWorker=window.Worker;
   async function inject(mode){
    const bytes=new Uint8Array([0,255,128,1]),digest=await sha256(bytes);
    window.Worker=class{
     terminate(){this.terminated=true}
     postMessage(m){if(m.type==='init'){this.id=m;queueMicrotask(()=>this.emit('ready'));return}if(m.type==='execute')queueMicrotask(()=>{
      this.emit('assets',{assets:[{name:'stale',bytes:0,sha256:'0'.repeat(64)}]},true);
      this.emit('assets',{assets:mode==='empty'?[]:[{name:'test.bin',bytes:4,sha256:digest}]});
      this.emit('asset-chunk',{name:'test.bin',offset:mode==='offset'?1:0,data:bytes.slice().buffer});
      this.emit('complete',{instructions:mode==='resource'?-1:10000,lua_memory_bytes:1000000});
      if(mode==='late'){window.Worker=RealWorker;window.__lateReplacement=patternClient.execute({command:'capabilities'});}
     })}
     emit(type,data={},stale=false){if(!this.terminated)this.onmessage?.({data:{schema_version:1,request_id:this.id.request_id,generation:this.id.generation+(stale?-1:0),type,...data}})}
    };
    try{return await patternClient.execute({command:'capabilities'})}finally{window.Worker=RealWorker}
   }
   await check('client-out-of-order-injected-stale',async()=>{const v=await inject('ok');assert(v.assets['test.bin'].length===4&&!v.assets.stale,'Stale response accepted');return {controlled_protocol_injection:true}});
   await check('client-supersede-during-asynchronous-output-digest',async()=>{
    const e=await rejects(inject('late'),'superseded');
    const newer=await window.__lateReplacement;
    assert(newer.generation===patternClient.generation && !newer.assets['test.bin'],'Late digest replaced newer real result');
    return {...e,newer_generation:newer.generation,controlled_old_response_injection:true,newer_worker_actual:true};
   });
   for(const mode of ['empty','offset','resource'])await check('client-injected-invalid-'+mode,()=>rejects(inject(mode),'invalid_response'));
   await check('immutable-cache-atomic-reuse-conflict-tamper',async()=>{
    const name='stage31-'+crypto.randomUUID(),cache=new ImmutableResultCache(name),bytes=new Uint8Array([0,255,128,1]);
    const value={schema_version:1,manifest:[{name:'x.bin',bytes:4,sha256:await sha256(bytes)}],assets:{'x.bin':bytes}};
    try{
     const mutable=structuredClone(value),saving=cache.put('captured',mutable);
     mutable.assets['x.bin'][0]=99;mutable.manifest[0].name='changed.bin';
     await saving;const captured=await cache.get('captured');
     assert(captured.assets['x.bin'][0]===0 && captured.manifest[0].name==='x.bin','Caller mutation corrupted asynchronous save');
     const concurrent=await Promise.all([cache.put('same',value),cache.put('same',value)]);
     assert(concurrent.filter(x=>x.reused).length===1,'Concurrent transaction failed');
     assert((await cache.get('same')).assets['x.bin'][1]===255,'Binary cache damaged');
     const different=structuredClone(value);different.assets['x.bin'][0]=2;different.manifest[0].sha256=await sha256(different.assets['x.bin']);
     await rejects(cache.put('same',different));assert((await cache.get('same')).assets['x.bin'][0]===0,'Conflict replaced immutable data');
     await rejects(cache.put('empty',{schema_version:1,manifest:[],assets:{}}));
     const bound=structuredClone(value);bound.source_digest=loaded.manifest.source_digest;bound.cache_key=await sha256(new TextEncoder().encode(bound.source_digest+'\n'+JSON.stringify(bound.manifest)));
     await cache.put(bound.cache_key,bound);await rejects(cache.put('wrong',bound));
     const db=await cache.open();await new Promise((resolve,reject)=>{const tx=db.transaction('results','readwrite'),s=tx.objectStore('results'),r=s.get('same');r.onsuccess=()=>{r.result.value.assets['x.bin'][0]=33;s.put(r.result,'same')};tx.oncomplete=resolve;tx.onabort=()=>reject(tx.error)});
     await rejects(cache.get('same'));return {concurrent_one_reused:true,conflict_preserved_original:true,corrupt_read_rejected:true,bound_identity_rejected:true,caller_mutation_snapshot_preserved:true};
    }finally{cache.close();indexedDB.deleteDatabase(name)}
   });
   await check('actual-worker-recovers-after-failures',async()=>{const v=await patternClient.execute({command:'capabilities'});assert(v.manifest.length>0,'Empty recovery');return {generation:v.generation}});
   return {status:'passed',source_digest:loaded.manifest.source_digest,user_agent:navigator.userAgent,checks:reports};
  }, {probe,vectors,nativeMicro});
  // A fresh worker still runs when all network requests are unavailable after load.
  await context.setOffline(true);
  const offline=await page.evaluate(async()=>{const a=await patternClient.execute({command:'capabilities'});patternClient.cancel();const b=await patternClient.execute({command:'capabilities'});return {first:a.manifest,second:b.manifest}});
  receipt.checks.push({name:'actual-offline-fresh-worker-restart',status:'passed',evidence:offline});
  receipt.browser=await browser.version();receipt.test_sha256=crypto.createHash('sha256').update(fs.readFileSync(__filename)).digest('hex');
  const out=args.output||path.join(__dirname,'../build/browser-check',receipt.source_digest);fs.mkdirSync(out,{recursive:true});fs.writeFileSync(path.join(out,'adversarial.json'),JSON.stringify(receipt,null,2)+'\n');console.log('Actual browser adversarial checks passed',receipt.checks.length,receipt.source_digest);
 }finally{await browser.close()}
}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1});
