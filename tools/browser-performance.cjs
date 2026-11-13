/* Shared Lua worker measurements; no browser geometry implementation. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),os=require('node:os');
const args=Object.fromEntries(process.argv.slice(2).map((v,i,a)=>v.startsWith('--')?[v.slice(2),a[i+1]]:null).filter(Boolean));
const pw=require(args.playwright||'playwright'),root=path.resolve(__dirname,'..');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
async function main(){
 const studioOnly=args['studio-only']==='true';
 const folder=path.resolve(args.recipes||path.join(root,'build/performance'));
 const manifest=JSON.parse(fs.readFileSync(path.join(folder,'workloads.json'),'utf8'));
 if(manifest.status!=='passed'||manifest.cases.length!==27)throw Error('Missing actual workload matrix');
 const out=path.join(root,'build',studioOnly?'browser-studio-performance':'browser-performance');fs.mkdirSync(out,{recursive:true});
 const browser=await pw.chromium.launch({headless:true,...(args.executable?{executablePath:args.executable}:{})});
 const report={status:'in_progress',browser:browser.version(),node:process.version,workloads_sha256:sha(fs.readFileSync(path.join(folder,'workloads.json'))),cases:[],bounds:[],scope:'Actual shared Wasmoon Lua5.4 worker with pinned host SHA. Fresh worker for each generate/replay; warm means verified assets/client reused, not a persistent solver session. JavaScript heap and worker Lua memory are distinct. Heartbeats measure this browser main thread, not a mobile or Pi device.'};
 report.runner_sha256=sha(fs.readFileSync(__filename));
 report.mode=studioOnly?'studio_only':'full_matrix';
 report.hardware_runtime={platform:os.platform(),release:os.release(),arch:os.arch(),logical_cpus:os.cpus().length,reported_cpu:os.cpus()[0]?.model??null,os_visible_ram_bytes:os.totalmem(),power_thermal_background_activity:'uncontrolled',whole_process_memory_limit:'not claimed'};
 const save=()=>fs.writeFileSync(path.join(out,'receipt.json'),JSON.stringify(report,null,2)+'\n');save();
 try{
  const page=await browser.newPage();await page.goto(args.url);await page.evaluate(()=>runtimeReady);
  report.source_digest=await page.evaluate(async()=>(await runtimeReady).manifest.source_digest);
  for(const row of (studioOnly?[]:manifest.cases)){
   const recipe=fs.readFileSync(path.join(folder,row.recipe_path),'utf8');if(sha(recipe)!==row.recipe_sha256)throw Error('Recipe changed');
   const value=await page.evaluate(async({recipe,row})=>{
    const {PatternWorkerClient,ImmutableResultCache}=await import('./client.js');
    const client=new PatternWorkerClient('./');await client.load();
    const decoder=new TextDecoder(),cache=new ImmutableResultCache('performance34-'+row.id);
    const phases=[];let original,clicks=0,ticks=0,last=performance.now(),maxGap=0;
    const button=document.createElement('button');button.textContent='Responsiveness probe';button.onclick=()=>clicks++;document.body.append(button);
    const timer=setInterval(()=>{const now=performance.now();maxGap=Math.max(maxGap,now-last);last=now;ticks++;button.click()},20);
    try{
     for(const phase of ['cold-generation','warm-assets-generation','validated-instance-replay']){
      const progress=[];let files={'recipe.json':recipe};
      if(phase==='validated-instance-replay'){
       files={};for(const [name,bytes]of Object.entries(original.assets))if(['recipe.json','instance.json','record.json'].includes(name)||/^block-[a-f0-9]{64}\.json$/.test(name))files[name]=bytes;
      }
      const options={command:phase==='validated-instance-replay'?'replay':'generate',files};
      if(phase==='validated-instance-replay'&&original.assets['instance-format.json'])options.instance_transport=JSON.parse(decoder.decode(original.assets['instance-format.json'])).schema;
      const start=performance.now(),result=await client.execute(options,{progress:p=>progress.push(p)}),elapsed=performance.now()-start;
      const semantic=Object.fromEntries(result.manifest.filter(x=>['instance.json','instance-format.json','scene.json','pattern.pdf','pattern.svg'].includes(x.name)||/^block-[a-f0-9]{64}\.json$/.test(x.name)).map(x=>[x.name,x.sha256]));
      if(original){for(const [name,digest]of Object.entries(semantic))if(original.manifest.find(x=>x.name===name)?.sha256!==digest)throw Error('Browser cold/warm/replay semantic drift '+name)}else original=result;
      phases.push({phase,elapsed_ms:elapsed,semantic,outputs:result.manifest,stats:result.stats,progress_count:progress.length,progress_first:progress[0],progress_last:progress.at(-1)});
     }
     const start=performance.now();await cache.put(original.cache_key,original);const cached=await cache.get(original.cache_key);
     if(!cached||JSON.stringify(cached.manifest)!==JSON.stringify(original.manifest))throw Error('Persistent cache changed manifests');
     for(const [name,b]of Object.entries(original.assets)){const c=cached.assets[name];if(b.length!==c.length||b.some((v,i)=>v!==c[i]))throw Error('Persistent cache changed actual bytes')}
     return {id:row.id,status:'passed',recipe_sha256:row.recipe_sha256,phases,cache_roundtrip_ms:performance.now()-start,cache_actual_bytes_equal:true,heartbeat:{interval_ms:20,ticks,clicks,maximum_observed_gap_ms:maxGap}};
    }finally{clearInterval(timer);button.remove();cache.close();client.cancel()}
   },{recipe,row});
   if(value.heartbeat.ticks<1||value.heartbeat.clicks!==value.heartbeat.ticks)throw Error('No responsive main-thread evidence');
   report.cases.push(value);save();console.log('Actual browser performance passed',row.id);
  }
  for(const row of (studioOnly?[]:manifest.cases.filter(r=>r.size==='large'))){
   const recipe=fs.readFileSync(path.join(folder,row.recipe_path),'utf8');
   const bounds=await page.evaluate(async({recipe,id})=>{
    const {PatternWorkerClient}=await import('./client.js');const client=new PatternWorkerClient('./');await client.load();const rows=[];
    for(const threshold of [1,3]){
     let progress=0,requested=false;const started=performance.now();
     try{await client.execute({command:'generate',files:{'recipe.json':recipe}},{progress:()=>{progress++;if(progress===threshold){requested=client.cancel()}}});throw Error('Cancelled workload accepted complete')}
     catch(e){if(e.code!=='cancelled'||!requested)throw e;rows.push({id,kind:'cancel',progress_threshold:threshold,progress_observed:progress,code:e.code,accepted_outputs:0,elapsed_ms:performance.now()-started})}
    }
    for(const controls of [{instructionLimit:1000},{instructionLimit:100000},{memoryLimitBytes:2097152},{watchdogMs:1}]){
     try{await client.execute({command:'generate',files:{'recipe.json':recipe}},controls);throw Error('Exhausted workload accepted complete')}
     catch(e){if(!['budget_exhausted','timeout','memory_budget'].includes(e.code))throw e;rows.push({id,kind:'resource_limit',controls,code:e.code,accepted_outputs:0,stats:e.stats})}
    }
    return rows;
   },{recipe,id:row.id});report.bounds.push(...bounds);save();console.log('Actual browser bounds passed',row.id);
  }
  // Exercise real studio controls while a full-page floral request is pending.
  const studio=await browser.newPage();await studio.goto(new URL('./',args.url).href);await studio.evaluate(()=>studioReady);
  await studio.locator('#family').selectOption('botanical-grown');await studio.locator('#generate').click();
  await studio.waitForFunction(()=>patternStudio.state.pending);
  await studio.waitForTimeout(1000);
  if(!await studio.evaluate(()=>patternStudio.state.pending))throw Error('Studio floral probe completed before its pending-interaction observation');
  const editStart=Date.now();await studio.locator('#seed').fill('102');
  await studio.waitForFunction(()=>!patternStudio.state.pending);
  if(await studio.evaluate(()=>patternStudio.state.result!==null))throw Error('Superseded studio generation overwrote state');
  const editMs=Date.now()-editStart;
  await studio.locator('#generate').click();
  await studio.waitForFunction(()=>patternStudio.state.pending&&patternStudio.state.recipe.design.seed===102&&patternStudio.state.recipe.design.extensions.legacy_geometry.seed===102);
  await studio.waitForTimeout(1000);
  const cancelStart=Date.now();await studio.locator('#cancel').click();await studio.waitForFunction(()=>!patternStudio.state.pending);
  if(!/Cancelled/.test(await studio.locator('#state').textContent())||await studio.evaluate(()=>patternStudio.state.result!==null))throw Error('Actual studio cancel accepted output');
  report.studio={status:'passed',family:'botanical-grown',edit_during_pending_ms:editMs,cancel_during_pending_ms:Date.now()-cancelStart,accepted_outputs:0,native_host_design_seed_synchronized:true,seed:await studio.locator('#seed').inputValue(),state:await studio.locator('#state').textContent()};
  await studio.screenshot({path:path.join(out,'studio-cancel.png'),fullPage:true});await studio.close();save();
  if(!studioOnly&&(report.cases.length!==27||report.bounds.length!==54))throw Error('Incomplete performance coverage');
  report.status='passed';save();
 }catch(e){report.status='failed';report.error=e.stack;save();throw e}finally{await browser.close()}
}
main().catch(e=>{console.error(e);process.exitCode=1});
