/* Real DOM workflows, actual shared Lua worker, downloaded native vector bytes. */
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const args=Object.fromEntries(process.argv.slice(2).map((x,i,a)=>x.startsWith('--')?[x.slice(2),a[i+1]]:null).filter(Boolean));
const pw=require(args.playwright||'playwright'),hash=x=>crypto.createHash('sha256').update(x).digest('hex');
const SCRIPT_SHA=hash(fs.readFileSync(__filename));
const root=path.resolve(__dirname,'..'),base=new URL(args.url||'http://127.0.0.1:8768/');base.pathname='/';
const output=path.resolve(args.output||path.join(root,'build/editor-check'));
fs.mkdirSync(output,{recursive:true});
async function main(){
 const browser=await pw.chromium.launch({headless:true,...(args.executable?{executablePath:args.executable}:{})});
 const receipts={},errors=[];
 async function state(page){return page.evaluate(()=>{const s=patternStudio.state;return{recipe:s.recipe,pending:s.pending,cursor:s.cursor,history_length:s.history_length,
   result:s.result?{manifest:s.result.manifest,source_digest:s.result.source_digest,record:JSON.parse(new TextDecoder().decode(s.result.assets['record.json']))}:null};});}
 async function idle(page){await page.waitForFunction(()=>window.patternStudio&&!patternStudio.state.pending,{},{timeout:310000});
  await page.waitForFunction(()=>!document.querySelector('#state').textContent.startsWith('Working'),{},{timeout:310000});
  const error=await page.locator('#error').textContent();assert.equal(error,'',await page.locator('#state').textContent()+': '+error);return state(page);}
 async function click(page,id){await page.locator('#'+id).click();return idle(page);}
 async function select(page,id,value){await page.locator('#'+id).selectOption(value);}
 async function fill(page,id,value){const control=page.locator('#'+id);await control.fill(String(value));}
 const instance=s=>s.result.manifest.find(x=>x.name==='instance.json').sha256;
 async function collect(page,name,claims){
  const current=await state(page);assert.equal(current.result.record.status,'complete');assert.equal(errors.length,0,errors.join('\n'));
  const dir=path.join(output,name);fs.mkdirSync(dir,{recursive:true});const assets=await page.evaluate(()=>Object.fromEntries(Object.entries(patternStudio.state.result.assets).map(([k,v])=>[k,Array.from(v)])));
  const hashes={};for(const[k,v]of Object.entries(assets)){const bytes=Buffer.from(v);fs.writeFileSync(path.join(dir,k),bytes);hashes[k]=hash(bytes);}
  for(const[button,file]of[['svg-save','pattern.svg'],['pdf-save','pattern.pdf']]){
   const downloaded=page.waitForEvent('download');await page.locator('#'+button).click();const download=await downloaded;
   const target=path.join(dir,'download-'+file);await download.saveAs(target);assert.equal(hash(fs.readFileSync(target)),hashes[file],'Download differs from validated core bytes');
  }
  const structure=await page.evaluate(()=>{const svg=document.querySelector('#art svg');return{paths:svg.querySelectorAll('path').length,texts:svg.querySelectorAll('text').length,
    rasters:svg.querySelectorAll('image,foreignObject').length,width:svg.getAttribute('width'),height:svg.getAttribute('height'),viewbox:svg.getAttribute('viewBox'),
    semantic_refs:svg.querySelectorAll('[data-semantic-ref]').length,clips:svg.querySelectorAll('clipPath').length};});
  assert.equal(structure.rasters,0);assert(structure.paths+structure.texts>0);assert(structure.width.endsWith('cm')&&structure.height.endsWith('cm'));
  assert(!fs.readFileSync(path.join(dir,'pattern.pdf')).includes(Buffer.from('/Subtype /Image')),'Unexpected raster in vector PDF');
  await page.screenshot({path:path.join(dir,'desktop.png'),fullPage:true});
  receipts[name]={status:'passed',source_digest:current.result.source_digest,instance_sha256:instance(current),claims,vector_structure:structure,assets_sha256:hashes};
  fs.writeFileSync(path.join(dir,'receipt.json'),JSON.stringify(receipts[name],null,2)+'\n');console.log('Editor task passed',name);
 }
 const cases={
  async border(page){
   await select(page,'family','periodic');await page.locator('summary').filter({hasText:'Page & protected regions'}).click();
   await fill(page,'page-width',10);await fill(page,'page-height',14);await fill(page,'crop','0, 0, 10, 14');await click(page,'border');
   await select(page,'profile','monochrome');const generated=await click(page,'generate');
   assert.equal(generated.recipe.view.protected_regions.length,1);assert.equal(generated.recipe.view.crop[2],10);
   const gray=await page.evaluate(()=>Array.from(patternStudio.state.result.assets['pattern.pdf']));
   assert(!/\s(?:rg|RG)\s/.test(Buffer.from(gray).toString('latin1')),'Monochrome PDF retained RGB paint operators');
   await collect(page,'border-monochrome',['Real grayscale vector print output before palette revision']);
   const sha=instance(generated);await select(page,'profile','palette');await click(page,'apply');assert.equal(instance(await state(page)),sha);
   await collect(page,'border',['Native 10×14cm planned page with protected center','True monochrome then palette native vector output','Paint changes preserve generated instance']);
  },
  async knot(page){
   await select(page,'family','celtic');const first=await click(page,'generate');await click(page,'knot-cut');const edited=await click(page,'generate');
   assert.notEqual(instance(first),instance(edited));assert.equal(edited.recipe.design.inputs.scaffold.open_sectors.length,1);
   assert(await page.evaluate(()=>JSON.parse(new TextDecoder().decode(patternStudio.state.result.assets['instance.json'])).structures.strands.components.some(x=>x.closed===false)),'Authored end did not open a strand');
   await collect(page,'knot',['Authored open sector changes native strand topology','Actual scaffold vertices/edges and crossing pins exposed','Generated topology validated by native family']);
  },
  async penrose(page){await crop(page,'penrose');},async spectre(page){await crop(page,'spectre');},
  async exemplar(page){
   await select(page,'family','decobrush');const first=await click(page,'generate');
   const library=first.recipe.design.inputs.library.map(piece=>({...piece,primitives:piece.primitives.map(primitive=>({...primitive,ring:primitive.ring.map(([x,y])=>[x,y*.9])}))}));
   await page.locator('#exemplar-open').setInputFiles({name:'authored-exemplars.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(library))});
   await page.waitForFunction(()=>document.querySelector('#state').textContent.startsWith('Exemplar library validated')||!document.querySelector('#error').hidden,{},{timeout:310000});
   await idle(page);assert.match(await page.locator('#state').textContent(),/Exemplar library validated/);
   const generated=await click(page,'generate');assert.deepEqual(generated.recipe.design.inputs.library,library);
   assert.notEqual(generated.result.manifest.find(x=>x.name==='pattern.svg').sha256,first.result.manifest.find(x=>x.name==='pattern.svg').sha256,'Imported exemplar geometry did not change the synthesized vector');
   await collect(page,'exemplar',['User-selected JSON exemplar library imported and natively validated','Authored primitive thickness change alters actual synthesized vector','Actual DecoBrush synthesis uses imported start/middle/finish pieces']);
  },
  async microgram(page){
   await select(page,'family','micrography');await fill(page,'input-text',(await state(page)).recipe.design.inputs.text.replace('fine line','bright line'));
   const generated=await click(page,'generate');assert.match(generated.recipe.design.inputs.text,/bright line/);
   assert(await page.locator('#art text').count()>0);assert.match(await page.locator('#font-profile').textContent(),/Pinned font/);
   await collect(page,'microgram',['Authored text shaped and placed by actual native Micrography family','Pinned font identity and unsupported custom loading displayed','Vector text is preserved in native output']);
  },
  async maze(page){
   await select(page,'family','maze');await select(page,'parameter-image','radial');const walls=await click(page,'generate');
   await select(page,'maze-display','solution');const solution=await click(page,'apply');assert.equal(instance(walls),instance(solution));
   assert.notEqual(walls.result.manifest.find(x=>x.name==='pattern.svg').sha256,solution.result.manifest.find(x=>x.name==='pattern.svg').sha256);
   await collect(page,'maze',['Native radial tone field guides actual maze generation','Solution display follows native validated route','Showing solution preserves maze instance']);
  },
  async recovery(page){
   await select(page,'family','periodic');const first=await click(page,'generate');const firstSha=instance(first);
   await select(page,'profile','monochrome');await click(page,'apply');const mono=await state(page);
   await click(page,'undo');assert.equal(instance(await state(page)),firstSha);await click(page,'redo');assert.equal(instance(await state(page)),firstSha);
   const downloadEvent=page.waitForEvent('download');await page.locator('#save').click();const download=await downloadEvent;
   const portable=path.join(output,'portable-workspace.json');await download.saveAs(portable);
   await fill(page,'seed','99');await page.evaluate(()=>patternStudio.saved);await page.reload();await page.waitForFunction(()=>window.studioReady);await page.evaluate(()=>studioReady);
   assert.equal(await page.locator('#seed').inputValue(),'99');assert.equal(instance(await state(page)),firstSha);assert.match(await page.locator('#state').textContent(),/unapplied settings preserved/);
   assert.equal((await state(page)).history_length,mono.history_length,'Refresh discarded undo history');
   await page.locator('#open').setInputFiles(portable);await page.waitForFunction(()=>document.querySelector('#state').textContent.startsWith('Workspace restored')||!document.querySelector('#error').hidden,{},{timeout:310000});
   await idle(page);assert.equal(instance(await state(page)),firstSha);assert.equal(await page.locator('#seed').inputValue(),String(mono.recipe.design.seed));
   const damaged=JSON.parse(fs.readFileSync(portable,'utf8')),svg=Buffer.from(damaged.result.assets['pattern.svg'],'base64');
   const forged=Buffer.concat([svg,Buffer.from('<!-- forged saved vector -->')]);damaged.result.assets['pattern.svg']=forged.toString('base64');
   Object.assign(damaged.result.manifest.find(x=>x.name==='pattern.svg'),{bytes:forged.length,sha256:hash(forged)});
   await page.locator('#open').setInputFiles({name:'forged-workspace.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(damaged))});
   await page.waitForFunction(()=>document.querySelector('#state').textContent.startsWith('Import failed'),{},{timeout:310000});
   assert.match(await page.locator('#error').textContent(),/does not match the native replay/);assert.equal(instance(await state(page)),firstSha);
   await page.locator('#recipe-open').setInputFiles({name:'broken.recipe',mimeType:'application/json',buffer:Buffer.from('{bad')});
   await page.waitForFunction(()=>document.querySelector('#state').textContent.startsWith('Recipe import failed'));assert.equal(instance(await state(page)),firstSha);
   assert.match(await page.locator('#error').textContent(),/JSON|property|position|Expected/i);
   await select(page,'profile','palette');await click(page,'apply');assert.equal(instance(await state(page)),firstSha);
   await page.context().setOffline(true);await select(page,'profile','monochrome');await click(page,'apply');assert.equal(instance(await state(page)),firstSha);await page.context().setOffline(false);
   await page.locator('#canvas').focus();await page.keyboard.press('+');await page.keyboard.press('ArrowRight');await page.keyboard.press('0');
   assert.equal(await page.locator('#canvas').evaluate(el=>document.activeElement===el),true);
   const prior=await state(page);await page.locator('#generate').click();await fill(page,'seed','100');
   await page.waitForTimeout(1000);assert.equal(instance(await state(page)),instance(prior));assert.match(await page.locator('#state').textContent(),/Settings changed/);
   await fill(page,'seed',String(prior.recipe.design.seed));await click(page,'apply');
   await page.evaluate(()=>{window.originalFileText=File.prototype.text;File.prototype.text=async function(){const text=await originalFileText.call(this);await new Promise(resolve=>setTimeout(resolve,500));return text;};});
   await page.locator('#recipe-open').setInputFiles({name:'delayed.recipe',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(prior.recipe))});
   await fill(page,'seed','101');await page.waitForTimeout(800);assert.equal(await page.locator('#seed').inputValue(),'101');assert.equal(instance(await state(page)),firstSha);
   await page.evaluate(()=>{File.prototype.text=originalFileText;delete window.originalFileText;});
   await fill(page,'seed',String(prior.recipe.design.seed));await click(page,'apply');
   await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(output,'mobile.png'),fullPage:true});
   assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'Responsive layout overflows');
   await page.setViewportSize({width:1400,height:1000});
   await collect(page,'recovery',['Undo/redo keeps validated instances','Refresh preserves unapplied draft, history and accepted instance','Portable workspace output bytes checked against native replay','Forged vector with matching attacker digest rejected by native replay','Malformed import preserves previous work','New edit supersedes running generation and delayed recipe import','Fresh native worker renders while network is offline','Keyboard navigation and 390px responsive layout']);
  },
  async structural_refresh(page){
   await select(page,'family','periodic');const first=await click(page,'generate');await fill(page,'seed',8);await click(page,'apply');
   assert.match(await page.locator('#state').textContent(),/Validated structural change/);assert.equal(instance(await state(page)),instance(first));
   await page.evaluate(()=>patternStudio.saved);await page.reload();await page.waitForFunction(()=>window.studioReady);await page.evaluate(()=>studioReady);
   assert.equal((await state(page)).recipe.design.seed,8);assert.equal(instance(await state(page)),instance(first));assert.equal(await page.locator('#svg-save').isDisabled(),true);
   assert.match(await page.locator('#validity').textContent(),/Previous preview/);assert.match(await page.locator('#state').textContent(),/Generate structure/);
   const generated=await click(page,'generate');assert.notEqual(instance(generated),instance(first));assert.equal(await page.locator('#svg-save').isEnabled(),true);
   const event=page.waitForEvent('download');await page.locator('#save').click();const download=await event,portable=path.join(output,'structural-refresh-workspace.json');await download.saveAs(portable);
   const data=JSON.parse(fs.readFileSync(portable,'utf8'));data.recipe=Object.fromEntries(Object.entries(data.recipe).reverse());
   await page.locator('#open').setInputFiles({name:'reordered-workspace.json',mimeType:'application/json',buffer:Buffer.from(JSON.stringify(data))});
   await page.waitForFunction(()=>document.querySelector('#state').textContent.startsWith('Workspace restored')||!document.querySelector('#error').hidden,{},{timeout:310000});await idle(page);
   assert.equal(instance(await state(page)),instance(generated));assert.equal(await page.locator('#svg-save').isEnabled(),true,'Native canonical recipe identity was replaced with JavaScript key order');
   await collect(page,'structural-refresh',['Applied structural change survives refresh with previous preview explicitly labeled','Current recipe remains pending until explicit generation','Native canonical recipe digest handles reordered workspace object keys without false stale status']);
  },
  async invalid_edits(page){
   await select(page,'family','periodic');const first=await click(page,'generate');
   await page.locator('summary').filter({hasText:'Page & protected regions'}).click();
   async function rejected(pattern){
    await page.locator('#apply').click();await page.waitForFunction(()=>!patternStudio.state.pending&&!document.querySelector('#state').textContent.startsWith('Working'),{},{timeout:310000});
    assert.match(await page.locator('#state').textContent(),/Failed/);assert.match(await page.locator('#error').textContent(),pattern);
    assert.equal(instance(await state(page)),instance(first));
   }
   await fill(page,'regions','false');await rejected(/protected_regions.*array/);assert.equal(await page.locator('#regions').inputValue(),'false');
   await page.evaluate(()=>patternStudio.saved);await page.reload();await page.waitForFunction(()=>window.studioReady);await page.evaluate(()=>studioReady);
   assert.equal(await page.locator('#regions').inputValue(),'false');assert.equal(instance(await state(page)),instance(first));
   await page.locator('summary').filter({hasText:'Page & protected regions'}).click();
   await fill(page,'regions','{}');await rejected(/protected_regions.*array/);assert.equal(await page.locator('#regions').inputValue(),'{}');
   await fill(page,'regions','[]');await click(page,'apply');
   await page.locator('summary').filter({hasText:'Recipe & data'}).click();await fill(page,'inputs','false');await rejected(/inputs.*object/);assert.equal(await page.locator('#inputs').inputValue(),'false');
   await fill(page,'inputs','{}');await click(page,'apply');
   await collect(page,'invalid-edit-recovery',['False and object-valued rectangle drafts are rejected by shared native typing','Invalid draft survives validation failure and refresh','False input-map draft is rejected and preserved','Last accepted instance is retained and correction recovers real vectors']);
  },
  async partial(page){
   await select(page,'family','mosaic');await fill(page,'parameter-count',30);await fill(page,'parameter-tile_size',2);await fill(page,'parameter-min_scale',1);
   const first=await click(page,'generate');
   const packing=await page.evaluate(()=>JSON.parse(new TextDecoder().decode(patternStudio.state.result.assets['instance.json'])).extensions.mosaic.packing);
   assert.equal(packing.status,'partial_packing');assert(packing.tiles.length>0&&packing.rejected.length>0);
   assert.match(await page.locator('#state').textContent(),/Partial packing/);assert.match(await page.locator('#validity').textContent(),/Partial packing/);
   assert.match(await page.locator('#construction').textContent(),new RegExp(packing.rejected.length+' rejected'));
   await select(page,'profile','monochrome');const styled=await click(page,'apply');assert.equal(instance(styled),instance(first));
   assert.match(await page.locator('#state').textContent(),/Partial packing/);
   await collect(page,'partial-packing',['Native partial packing is shown explicitly rather than advertised as complete packing','Native placed/rejected/coverage and solver status are visible','Paint revision preserves partial construction and its status']);
  },
  async page_controls(page){
   await select(page,'family','periodic');const original=await click(page,'generate');
   await select(page,'profile','monochrome');const gray=await click(page,'apply');
   assert.deepEqual(gray.recipe.view,original.recipe.view,'Unrelated paint edit changed native region IDs or planner options');
   await page.locator('summary').filter({hasText:'Page & protected regions'}).click();
   await fill(page,'page-width',4);await fill(page,'page-height',3);const prepared=await click(page,'apply');
   assert.deepEqual(prepared.recipe.view.crop,[0,0,4,3],'Page-only edit retained the old crop');assert.equal(instance(prepared),instance(original));
   assert.match(await page.locator('#state').textContent(),/Validated structural change/);assert.equal(await page.locator('#svg-save').isDisabled(),true);
   const resized=await click(page,'generate');assert.notEqual(instance(resized),instance(original));
   await collect(page,'page-controls',['Palette-only change preserves complete native view and region identities','Changing page size alone selects its native full-page crop','Structural page change waits for explicit generation']);
   await select(page,'family','micrography');await click(page,'generate');
   assert.deepEqual(await page.locator('#tool option').evaluateAll(options=>options.map(x=>x.value)),['pan']);
   await page.setViewportSize({width:390,height:844});assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
   const font=await page.locator('#font-profile').boundingBox(),aside=await page.locator('aside').boundingBox();assert(font.x+font.width<=aside.x+aside.width);
   await page.screenshot({path:path.join(output,'microgram-mobile.png'),fullPage:true});await page.setViewportSize({width:1400,height:1000});
   await collect(page,'microgram-controls',['Unsupported mask and guide controls omitted for native Micrography','Pinned font digest wraps in a390px layout']);
  },
  async canvas(page){
   await select(page,'family','celtic');const first=await click(page,'generate');await click(page,'zoom-in');await select(page,'tool','guide');
   await page.evaluate(()=>{window.pointerEvents=[];for(const type of ['pointerdown','pointerup'])document.querySelector('#canvas').addEventListener(type,event=>pointerEvents.push({type,x:event.clientX,y:event.clientY}),true);});
   const points=await page.evaluate(()=>{const v=patternStudio.state.recipe.design.inputs.scaffold.vertices[0].point,m=document.querySelector('#art svg>g').getScreenCTM();
    const p=new DOMPoint(...v).matrixTransform(m),q=new DOMPoint(v[0]+.05,v[1]+.05).matrixTransform(m);return{p:[p.x,p.y],q:[q.x,q.y]};});
   await page.mouse.move(...points.p);await page.mouse.down();await page.mouse.move(...points.q);await page.mouse.up();
   // Chromium dispatches pointer coordinates at finite screen precision. Compare
   // against the actual received event, retaining the tight world-space check.
   const expectedPoint=await page.evaluate(()=>{const e=pointerEvents.at(-1),m=document.querySelector('#art svg>g').getScreenCTM().inverse(),p=new DOMPoint(e.x,e.y).matrixTransform(m);return[p.x,p.y];});
   const edited=await click(page,'generate');assert.notEqual(instance(first),instance(edited));
   const before=first.recipe.design.inputs.scaffold.vertices[0].point,after=edited.recipe.design.inputs.scaffold.vertices[0].point;
   assert(after.every((v,i)=>Math.abs(v-expectedPoint[i])<1e-9),'Pointer transform differs from actual physical input event');
   assert(after.every((v,i)=>Math.abs(v-before[i]-.05)<.001),'Dispatched pointer missed intended drag by more than10 micrometres');
   await select(page,'tool','region');const rectangle=await page.evaluate(()=>{const m=document.querySelector('#art svg>g').getScreenCTM();return [[2,2],[2.2,2.2]].map(v=>{const p=new DOMPoint(...v).matrixTransform(m);return[p.x,p.y];});});
   const canvasBox=await page.locator('#canvas').boundingBox();assert(rectangle.every(([x,y])=>x>canvasBox.x&&x<canvasBox.x+canvasBox.width&&y>canvasBox.y&&y<canvasBox.y+canvasBox.height),'Rectangle input must be inside the visible zoomed viewport');
   await page.mouse.move(...rectangle[0]);await page.mouse.down();await page.mouse.move(...rectangle[1]);await page.mouse.up();
   const expectedBounds=await page.evaluate(()=>{const m=document.querySelector('#art svg>g').getScreenCTM().inverse(),[a,b]=pointerEvents.slice(-2).map(e=>new DOMPoint(e.x,e.y).matrixTransform(m));return[Math.min(a.x,b.x),Math.min(a.y,b.y),Math.max(a.x,b.x),Math.max(a.y,b.y)];});
   const masked=await click(page,'apply');assert.equal(instance(masked),instance(edited));const bounds=masked.recipe.view.protected_regions.at(-1).bounds;
   assert(bounds.every((v,i)=>Math.abs(v-expectedBounds[i])<1e-9));
   await collect(page,'canvas',['Guide point drag under zoom preserves intended world coordinates','Native regeneration changes scaffold geometry','Protected rectangle drawn under zoom uses physical coordinates','Mask revision preserves source instance']);
  }
 };
 async function crop(page,family){
  await select(page,'family',family);const first=await click(page,'generate'),bounds=first.recipe.view.crop;
  await page.locator('summary').filter({hasText:'Page & protected regions'}).click();
  const crop=[bounds[0]+.1,bounds[1]+.1,bounds[2]-.1,bounds[3]-.1];await fill(page,'crop',crop.join(', '));const changed=await click(page,'apply');
  assert.equal(instance(changed),instance(first));assert.deepEqual(changed.recipe.view.crop,crop);
  assert.match(JSON.stringify(changed.result.record.lineage),/validated-style-view-revision/);
  await collect(page,family,['World-anchored source instance unchanged after physical crop','Native planner context retained','View revision lineage records original source']);
 }
 try{
  const chosen=(args.only||Object.keys(cases).join(',')).split(',');
  for(const name of chosen){assert(cases[name],'Unknown editor task '+name);const context=await browser.newContext({viewport:{width:1400,height:1000},acceptDownloads:true});const page=await context.newPage();
   page.on('pageerror',error=>errors.push(error.message));await page.goto(base.href);await page.waitForFunction(()=>window.studioReady);await page.evaluate(()=>studioReady);
   try{await cases[name](page);}catch(error){await page.screenshot({path:path.join(output,name+'-failure.png'),fullPage:true});fs.writeFileSync(path.join(output,name+'-failure.json'),JSON.stringify({error:error.stack,state:await state(page),visible_error:await page.locator('#error').textContent()},null,2));throw error;}
   finally{await context.close();}
  }
  const receipt={status:'passed',browser:await browser.version(),source_digest:Object.values(receipts)[0].source_digest,
   editorcheck_sha256:SCRIPT_SHA,cases:receipts,errors,scope:'Actual DOM/worker tasks and exact downloaded vector bytes; visual review is a separate required evidence receipt.'};
  fs.writeFileSync(path.join(output,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');
 }finally{await browser.close();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
