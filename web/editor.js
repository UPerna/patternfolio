import {PatternWorkerClient} from './client.js';
import {sha256} from './cache.js';
const $ = id => document.getElementById(id), decode = bytes => new TextDecoder('utf-8', {fatal:true}).decode(bytes);
const clone = value => structuredClone(value), pretty = value => JSON.stringify(value, null, 2);
const client = window.patternClient = new PatternWorkerClient('./');
window.runtimeReady = client.load();
let loaded, catalog, recipe, recipeDigest, result = null, history = [], cursor = -1, drafts = {}, epoch = 0, pending = false;
let navigation = {zoom:1,x:0,y:0}, drag = null, saveChain = Promise.resolve(), database;
const parameterInputs = new Map(), inputEditors = new Map();
const nativeSummaries = new WeakMap();
function nativeSummary(value) {
  if(nativeSummaries.has(value))return nativeSummaries.get(value);
  const instance=jsonAsset(value,'instance.json'),details=[];let label='Complete';
  for(const[family,payload]of Object.entries(instance.extensions??{})){
    if(!payload||typeof payload!=='object')continue;
    if(payload.packing&&typeof payload.packing.status==='string'){
      const packing=payload.packing,detail={family,kind:'packing',status:packing.status};
      if(Array.isArray(packing.tiles))detail.placed=packing.tiles.length;
      if(Array.isArray(packing.rejected))detail.rejected=packing.rejected.length;
      if(Number.isFinite(packing.coverage))detail.coverage=packing.coverage;
      details.push(detail);
      if(packing.status==='partial_packing')label='Partial packing';
      if(packing.status==='empty_packing')label='Empty packing';
    }
    if(payload.solver&&typeof payload.solver.status==='string')details.push({family,kind:'solver',status:payload.solver.status});
  }
  const text=details.map(item=>{
    let message=title(item.kind)+': '+title(item.status);
    if(item.placed!==undefined)message+=' · '+item.placed+' placed';
    if(item.rejected!==undefined)message+=' · '+item.rejected+' rejected';
    if(item.coverage!==undefined)message+=' · '+(100*item.coverage).toFixed(1)+'% coverage';
    return message;
  }).join('. ');
  const summary={label,details,text:text||'Native construction validated.'};nativeSummaries.set(value,summary);return summary;
}
function message(text, error = null) {
  $('state').textContent = text; $('error').hidden = !error; $('error').textContent = error?.message ?? '';
}
function invalidate() {
  epoch++; client.cancel(); pending = false; $('cancel').hidden = true;
  if (recipe) message('Settings changed · apply to validate');
  enableExports(false);
}
function enableExports(ready) {
  $('svg-save').disabled = !ready || !result?.assets['pattern.svg'];
  $('pdf-save').disabled = !ready || !result?.assets['pattern.pdf'];
  $('network-save').hidden = !ready || !result?.assets['network.json'];
}
function isCurrentResult(){return Boolean(result&&result.source_digest===loaded.manifest.source_digest&&result.manifest.find(row=>row.name==='recipe.json')?.sha256===recipeDigest);}
function captureDrafts() {
  const values = {};
  for (const el of document.querySelectorAll('#settings input,#settings select,#settings textarea,#inputs')) {
    if (el.id) values[el.id] = el.type === 'checkbox' ? el.checked : el.value;
  }
  return values;
}
async function db() {
  if (!database) database = new Promise((resolve,reject) => {
    const request = indexedDB.open('florilegium-studio-v1',1);
    request.onupgradeneeded = () => request.result.createObjectStore('workspaces');
    request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
  });
  return database;
}
async function store(value) {
  const connection = await db();
  await new Promise((resolve,reject) => {
    const tx = connection.transaction('workspaces','readwrite');tx.objectStore('workspaces').put(value,'current');
    tx.oncomplete = resolve; tx.onerror = () => reject(tx.error);tx.onabort = () => reject(tx.error ?? Error('Save aborted'));
  });
}
function snapshot() {
  return {schema_version:1,kind:'florilegium-workspace',source_digest:loaded.manifest.source_digest,
    recipe:clone(recipe),result:clone(result),history:clone(history),cursor,drafts:clone(drafts),navigation:clone(navigation)};
}
function persist() {
  if (!recipe) return;
  const value = snapshot();
  saveChain = saveChain.catch(()=>{}).then(()=>store(value)).then(()=>{
    $('saved').textContent='Saved in this browser · export a workspace for a portable backup.';
  }).catch(error=>{$('saved').textContent='Browser save failed: '+error.message+'. Export a workspace now.';});
}
function remember() {
  history = history.slice(0,cursor+1);history.push({recipe:clone(recipe),result:clone(result)});
  if(history.length>12) history.shift();cursor=history.length-1;historyButtons();
}
function historyButtons() { $('undo').disabled = cursor<=0; $('redo').disabled = cursor>=history.length-1; }
function title(text) { return text.replaceAll('-',' ').replaceAll('_',' '); }
function label(text, control, parent) {
  const el=document.createElement('label');el.append(document.createTextNode(text),control);parent.append(el);return el;
}
function pageSize(q) {
  const planned=q.view.extensions?.document_planning;
  if(planned)return planned.document.pages.find(p=>p.id===planned.page_id).size;
  const b=q.design.document.bounds;return [b[2]-b[0],b[3]-b[1]];
}
function colorHex(rgb) { return '#'+rgb.map(c=>Math.round(c*255).toString(16).padStart(2,'0')).join(''); }
function colorRgb(hex) { return [1,3,5].map(i=>parseInt(hex.slice(i,i+2),16)/255); }
function editorInput(name, value, parent, rows=5) {
  const textarea=document.createElement('textarea');textarea.id='input-'+name;textarea.rows=rows;textarea.spellcheck=false;
  textarea.value=typeof value==='string'?value:pretty(value);textarea.dataset.inputName=name;
  label(title(name),textarea,parent);inputEditors.set(name,{element:textarea,string:typeof value==='string'});return textarea;
}
function buildForm() {
  const row=catalog.find(x=>x.family===recipe.definition.id);
  $('family').value=row?.id??''; $('title').textContent=title(row?.id??recipe.definition.family);
  $('family-note').textContent=recipe.definition.assumptions.join(' · ');
  $('seed').value=recipe.design.seed; $('parameters').replaceChildren();parameterInputs.clear();inputEditors.clear();
  for(const [name,value] of Object.entries(recipe.design.parameters)) {
    const schema=recipe.definition.parameters[name];if(!schema)continue;
    let control;
    if(schema.enum){control=document.createElement('select');for(const v of schema.enum)control.add(new Option(String(v),String(v)));}
    else{control=document.createElement('input');control.type=typeof value==='boolean'?'checkbox':typeof value==='number'?'number':'text';
      if(schema.minimum!==undefined)control.min=schema.minimum;if(schema.maximum!==undefined)control.max=schema.maximum;
      if(control.type==='number')control.step=schema.type==='integer'?'1':'any';}
    control.id='parameter-'+name;if(control.type==='checkbox')control.checked=value;else control.value=value;
    parameterInputs.set(name,{control,type:typeof value});label(title(name),control,$('parameters'));
  }
  const inputs=recipe.design.inputs, panel=$('family-inputs');panel.replaceChildren();
  const canMask=recipe.definition.id!=='text/digital-micrography';
  const oldTool=$('tool').value;
  $('tool').replaceChildren(new Option('Pan','pan'),...(canMask?[new Option('Protect rectangle','region')]:[]),
    ...(inputs.guide||inputs.scaffold?[new Option('Move guide / scaffold point','guide')]:[]));
  if([...$('tool').options].some(option=>option.value===oldTool))$('tool').value=oldTool;
  $('regions').closest('label').hidden=!canMask;$('regions-help').hidden=!canMask;$('border').hidden=!canMask;
  for(const key of ['text','guide','scaffold','library','field','holes','entry','exit'])if(inputs[key]!==undefined)editorInput(key,inputs[key],panel,key==='text'?6:5);
  if(inputs.scaffold){
    const button=document.createElement('button');button.type='button';button.id='knot-cut';button.textContent='Toggle authored strand end';
    button.onclick=()=>{try{const scaffold=JSON.parse(inputEditors.get('scaffold').element.value),edge=scaffold.edges[0];
      scaffold.open_sectors=scaffold.open_sectors?.length?[]:[{vertex:edge.from,edge:edge.id}];
      inputEditors.get('scaffold').element.value=pretty(scaffold);changed();}catch(error){message('Scaffold needs correction',error);}};panel.append(button);
    const help=document.createElement('p');help.className='helper';help.textContent='Edit vertices and edges to change topology. Pin crossings with scaffold.above: {"edge-id":"L"} or "R". Inconsistent alternation is rejected.';panel.append(help);
  }
  if(inputs.font){const note=document.createElement('p');note.className='helper';note.id='font-profile';
    note.textContent='Pinned font: '+inputs.font.family+' · '+(inputs.font.sha256??inputs.font.font_sha256??'font digest in recipe')+'. The native glyph profile validates script support. Custom font loading is unavailable.';panel.append(note);}
  if(recipe.definition.id.includes('maze')){const note=document.createElement('p');note.className='helper';
    note.textContent='Image guidance uses native ramp, radial, ribbon or constant tone fields. Guide points steer the tree. Arbitrary bitmap input is unavailable in this family.';panel.append(note);}
  $('inputs').value=pretty(inputs);$('exemplar-label').hidden=!Array.isArray(inputs.library);
  const size=pageSize(recipe);$('page-width').value=size[0];$('page-height').value=size[1];
  $('crop').value=recipe.view.crop.join(', ');$('regions').value=pretty(recipe.view.protected_regions);
  const profile=recipe.design.style.output_profile??{mode:'source'};$('profile').value=profile.mode;
  $('inks').hidden=profile.mode!=='palette';if(profile.mode==='palette'){$('fill').value=colorHex(profile.fill);$('stroke').value=colorHex(profile.stroke);}
  const familyStyle=$('family-style');familyStyle.replaceChildren();
  if(recipe.definition.id.includes('maze')){
    const select=document.createElement('select');select.id='maze-display';select.add(new Option('Maze walls','walls'));select.add(new Option('Solution route','solution'));
    select.value=recipe.design.style.display??'walls';label('Maze display',select,familyStyle);
  }
  for(const[id,value]of Object.entries(drafts)){const el=$(id);if(!el||(!el.closest('#settings')&&id!=='inputs'))continue;if(el.type==='checkbox')el.checked=value;else el.value=value;}
  historyButtons();drawOverlay();
}
function changed(){invalidate();drafts=captureDrafts();persist();drawOverlay();}
function readEdits(){
  if(!$('settings').reportValidity())throw Error('Correct the highlighted settings first.');
  const parameters={};for(const[name,{control,type}]of parameterInputs){parameters[name]=type==='number'?Number(control.value):type==='boolean'?control.checked:control.value;}
  const inputs=JSON.parse($('inputs').value);
  for(const[name,{element,string}]of inputEditors){
    const original=recipe.design.inputs[name];const current=string?element.value:JSON.parse(element.value);
    if(JSON.stringify(current)!==JSON.stringify(original))inputs[name]=current;
  }
  const style=clone(recipe.design.style),mode=$('profile').value;
  style.output_profile={schema_version:1,mode};if(mode==='palette'){style.output_profile.fill=colorRgb($('fill').value);style.output_profile.stroke=colorRgb($('stroke').value);}
  if($('maze-display'))style.display=$('maze-display').value;
  const crop=$('crop').value.split(',').map(v=>Number(v.trim()));
  if(crop.length!==4||crop.some(v=>!Number.isFinite(v))||crop[2]<=crop[0]||crop[3]<=crop[1])throw Error('Crop needs four finite coordinates with positive width and height.');
  const edits={schema_version:1,seed:Number($('seed').value),parameters,inputs,style,crop,protected_regions:JSON.parse($('regions').value)};
  // Unchanged view fields are not new authored edits: retain native region IDs
  // and planner options, and let a page resize choose its new full-page crop.
  if(JSON.stringify(crop)===JSON.stringify(recipe.view.crop))delete edits.crop;
  if(JSON.stringify(edits.protected_regions)===JSON.stringify(recipe.view.protected_regions))delete edits.protected_regions;
  const size=[Number($('page-width').value),Number($('page-height').value)];
  if(JSON.stringify(size)!==JSON.stringify(pageSize(recipe)))edits.page_size=size;
  return edits;
}
async function run(command,files,extras={},token=++epoch){
  pending=true;$('cancel').hidden=false;enableExports(false);message('Working · '+command);
  try{const value=await client.execute({command,files,...extras},{progress:p=>{
    if(token===epoch)message('Working · '+p.phase+(p.lua_memory_bytes?' · '+Math.round(p.lua_memory_bytes/1048576)+' MB Lua':''));
  }});if(token!==epoch)throw Object.assign(Error('A newer edit superseded this operation'),{code:'superseded'});return value;
  }finally{if(token===epoch){pending=false;$('cancel').hidden=true;}}
}
function jsonAsset(value,name){if(!value.assets[name])throw Error('Core omitted '+name);return JSON.parse(decode(value.assets[name]));}
async function apply(generate=false){
  invalidate();const token=epoch;
  try{
    const prepared=await run('validate',{'recipe.json':JSON.stringify(recipe)},{edits:readEdits()},token);
    const candidate=jsonAsset(prepared,'recipe.json'),receipt=jsonAsset(prepared,'edit-receipt.json');
    const currentResult=result;
    recipe=candidate;recipeDigest=jsonAsset(prepared,'report.json').recipe_sha256;drafts={};remember();buildForm();persist();
    const structuralDigest=jsonAsset(prepared,'report.json').structural_input_sha256;
    const structuralChange=receipt.structural_change||(currentResult&&currentResult.structural_input_sha256!==structuralDigest);
    if(!generate&&(!currentResult||structuralChange)){
      display();
      message(structuralChange?'Validated structural change · select Generate structure':'Recipe validated · select Generate structure');
      $('validity').textContent=result?'Previous preview · Generate structure':'Validated recipe · not generated';return;
    }
    const files={'recipe.json':JSON.stringify(recipe)};let command='generate',extras={};
    if(!generate&&currentResult){
      command='render';Object.assign(files,replayFiles(currentResult));files['previous-recipe.json']=decode(currentResult.assets['recipe.json']);
      files['recipe.json']=JSON.stringify(recipe);extras.previous_recipe=true;
      if(currentResult.assets['instance-format.json'])extras.instance_transport='legacy-neutral-bundle@1';
    }
    const value=await run(command,files,{formats:['svg','pdf'],...extras},token);
    const record=jsonAsset(value,'record.json');if(record.status!=='complete')throw Error('Pattern is '+record.status+': '+pretty(record.diagnostics));
    safeSvg(value.assets['pattern.svg']);
    value.structural_input_sha256=structuralDigest;
    result=value;remember();display();persist();message(nativeSummary(value).label+' · '+(command==='render'?'existing structure preserved':'structure generated and validated'));
  }catch(error){if(token!==epoch)return;message(error.code==='cancelled'?'Cancelled · previous work preserved':'Failed · previous work preserved',error);$('validity').textContent='Failed edit · previous preview';persist();}
}
function replayFiles(value){const files={};for(const[name,bytes]of Object.entries(value.assets))if(['recipe.json','instance.json','record.json','instance-format.json'].includes(name)||name.startsWith('block-'))files[name]=bytes;return files;}
function safeSvg(bytes){
  const document=new DOMParser().parseFromString(decode(bytes),'image/svg+xml');
  if(document.querySelector('parsererror')||document.documentElement.localName!=='svg')throw Error('Core SVG could not be parsed');
  for(const el of document.querySelectorAll('*')){
    if(!['svg','g','path','defs','clipPath','symbol','use','text','tspan','rect','circle','line','polyline','polygon','title','desc','style'].includes(el.localName))throw Error('SVG contains an unsupported element: '+el.localName);
    if(el.localName==='style'&&!/^@font-face\{font-family:SceneFont\d+;src:url\(data:font\/otf;base64,[A-Za-z0-9+/=]+\) format\("opentype"\);\}$/.test(el.textContent))throw Error('SVG contains an unsupported stylesheet');
    for(const attr of [...el.attributes])if(/^on/i.test(attr.name)||(attr.localName==='href'&&!attr.value.startsWith('#'))||(/url\(/i.test(attr.value)&&!/url\(#[\w.-]+\)/.test(attr.value)))throw Error('SVG contains an external or active reference');
  }
  return document.importNode?window.document.importNode(document.documentElement,true):document.documentElement;
}
function display(){
  if(result?.assets['pattern.svg']){$('art').replaceChildren(safeSvg(result.assets['pattern.svg']));document.querySelector('.empty').hidden=true;}
  else{$('art').replaceChildren();document.querySelector('.empty').hidden=false;}
  if(result){const record=jsonAsset(result,'record.json'),construction=nativeSummary(result),previewRecipe=jsonAsset(result,'recipe.json');
    $('validity').textContent=isCurrentResult()?(construction.label==='Complete'?record.status:construction.label+' · validated')+' · '+previewRecipe.view.validity:'Previous preview · Generate structure';
    $('construction').textContent=(isCurrentResult()?'':'Current recipe awaits generation; showing the previous validated construction. ')+construction.text;
    $('diagnostics').textContent=pretty({status:record.status,mathematics:previewRecipe.definition.assumptions,validation:record.validation,diagnostics:record.diagnostics,
      construction:construction.details,source_digest:result.source_digest,instance_sha256:result.manifest.find(x=>x.name==='instance.json')?.sha256,lineage:record.lineage,statistics:result.stats});}
  else{$('validity').textContent='Not generated';$('construction').textContent='';$('diagnostics').textContent='No validated instance yet.';}
  // The actual Lua canonical recipe digest decides result identity. JavaScript
  // object key order never substitutes for the core's recipe encoding.
  transform();enableExports(isCurrentResult());
}
function transform(){const svg=$('art').firstElementChild;if(svg){
  const box=svg.viewBox.baseVal,ratio=box.width/box.height,w=$('art').clientWidth,h=$('art').clientHeight;
  svg.style.width=Math.min(w,h*ratio)+'px';svg.style.height=Math.min(h,w/ratio)+'px';
  svg.style.transform=`translate(${navigation.x}px,${navigation.y}px) scale(${navigation.zoom})`;
}drawOverlay();}
function worldGroup(){return $('art').querySelector('svg>g');}
function worldPoint(event){const group=worldGroup();if(!group)return null;return new DOMPoint(event.clientX,event.clientY).matrixTransform(group.getScreenCTM().inverse());}
function screenPoint(x,y){const p=new DOMPoint(x,y).matrixTransform(worldGroup().getScreenCTM());const b=$('canvas').getBoundingClientRect();return[p.x-b.left,p.y-b.top];}
function guidePoints(){try{const inputs=JSON.parse($('inputs').value),points=[];
  if(inputEditors.has('scaffold')){const scaffold=JSON.parse(inputEditors.get('scaffold').element.value);scaffold.vertices.forEach((v,i)=>points.push({kind:'scaffold',index:i,point:v.point}));}
  if(inputEditors.has('guide'))JSON.parse(inputEditors.get('guide').element.value).forEach((v,i)=>points.push({kind:'guide',index:i,point:Array.isArray(v)?v:[v.x,v.y]}));
  return points;}catch{return[];}}
function overlayElement(name,attrs){const el=document.createElementNS('http://www.w3.org/2000/svg',name);for(const[k,v]of Object.entries(attrs))el.setAttribute(k,v);$('overlay').append(el);return el;}
function drawOverlay(){
  $('overlay').replaceChildren();if(!$('overlays').checked||!worldGroup())return;
  try{for(const region of JSON.parse($('regions').value)){const b=region.bounds,a=screenPoint(b[0],b[1]),z=screenPoint(b[2],b[3]);
    overlayElement('rect',{x:Math.min(a[0],z[0]),y:Math.min(a[1],z[1]),width:Math.abs(a[0]-z[0]),height:Math.abs(a[1]-z[1]),fill:'#cc733622',stroke:'#8c4618','stroke-dasharray':'5 3'});}
    for(const item of guidePoints()){const p=screenPoint(...item.point);overlayElement('circle',{cx:p[0],cy:p[1],r:5,fill:'#fff',stroke:'#285342','stroke-width':2});}
  }catch{/* Invalid drafts are retained until native validation reports the error. */}
}
function download(name,bytes,type){const url=URL.createObjectURL(new Blob([bytes],{type})),a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}
function base64(bytes){let text='';for(let i=0;i<bytes.length;i+=16384)text+=String.fromCharCode(...bytes.subarray(i,i+16384));return btoa(text);}
function encodedResult(value){if(!value)return null;return{...value,assets:Object.fromEntries(Object.entries(value.assets).map(([k,v])=>[k,base64(v)]))};}
async function verifiedResult(value,token){
  if(!value)return null;if(value.source_digest!==loaded.manifest.source_digest)throw Error('Saved instance uses a different core revision. Import its recipe and regenerate; the original workspace is preserved.');
  if(!Array.isArray(value.manifest)||value.manifest.length>1024)throw Error('Workspace asset manifest invalid');
  let total=0;const assets={};for(const row of value.manifest){if(!/^[\w.-]{1,160}$/.test(row.name)||assets[row.name]||!Number.isSafeInteger(row.bytes)||row.bytes<0||(total+=row.bytes)>64*1024*1024)throw Error('Workspace asset budget or name invalid');
    const raw=value.assets[row.name],bytes=typeof raw==='string'?Uint8Array.from(atob(raw),c=>c.charCodeAt(0)):raw;
    if(!(bytes instanceof Uint8Array)||bytes.length!==row.bytes||await sha256(bytes)!==row.sha256)throw Error('Damaged workspace asset: '+row.name);assets[row.name]=bytes;}
  if(token!==epoch)throw Error('Import superseded by a newer edit');
  const candidate={...value,assets};const proof=await run('render',replayFiles(candidate),{formats:['svg','pdf'],...(assets['instance-format.json']?{instance_transport:'legacy-neutral-bundle@1'}:{})},token);
  if(jsonAsset(proof,'record.json').status!=='complete')throw Error('Saved instance validation failed');
  for(const name of ['instance.json','scene.json','view.json','recipe.json','pattern.svg','pattern.pdf']){
    if(!assets[name]||!proof.assets[name]||await sha256(assets[name])!==await sha256(proof.assets[name]))throw Error('Saved output does not match the native replay: '+name);
  }
  safeSvg(assets['pattern.svg']);return candidate;
}
async function readFile(input,max=96*1024*1024){const file=input.files[0];if(!file)throw Error('Choose a file first.');if(file.size>max)throw Error('File exceeds the bounded import size.');return JSON.parse(await file.text());}
async function importWorkspace(value,restore=false,token=++epoch){
  if(token!==epoch)throw Error('Import superseded by a newer edit');
  if(value.kind!=='florilegium-workspace'||value.schema_version!==1)throw Error('Expected a Florilegium workspace, version 1.');
  const validated=await run('validate',{'recipe.json':JSON.stringify(value.recipe)},{},token);
  if(jsonAsset(validated,'report.json').status!=='complete')throw Error('Workspace recipe invalid');
  const accepted=await verifiedResult(value.result,token);
  if(token!==epoch)throw Error('Import superseded by a newer edit');
  if(accepted){const validation=await run('validate',{'recipe.json':decode(accepted.assets['recipe.json'])},{},token);accepted.structural_input_sha256=jsonAsset(validation,'report.json').structural_input_sha256;}
  recipe=clone(value.recipe);recipeDigest=jsonAsset(validated,'report.json').recipe_sha256;result=accepted;drafts=value.drafts??{};
  // Imported history is not trusted evidence. The current instance is validated;
  // keep the previous local workspace as the undo point and import atomically.
  if(restore&&Array.isArray(value.history)&&value.history.length>0&&value.history.length<=12&&Number.isInteger(value.cursor)&&value.cursor>=0&&value.cursor<value.history.length){
    history=clone(value.history);cursor=value.cursor;history[cursor]={recipe:clone(recipe),result:clone(result)};historyButtons();
  }else{if(restore){history=[];cursor=-1;}remember();}
  navigation=value.navigation??{zoom:1,x:0,y:0};
  if(!Number.isFinite(navigation.zoom)||navigation.zoom<.1||navigation.zoom>20||![navigation.x,navigation.y].every(Number.isFinite))navigation={zoom:1,x:0,y:0};
  buildForm();display();persist();message('Workspace restored · saved instance validated');
  if(Object.keys(drafts).length){enableExports(false);message('Workspace restored · unapplied settings preserved');}
  else if(result&&!isCurrentResult())message('Workspace restored · recipe changes need Generate structure');
}
$('settings').addEventListener('input',changed);$('inputs').addEventListener('input',changed);
for(const fileLabel of document.querySelectorAll('label.button')){fileLabel.tabIndex=0;fileLabel.setAttribute('role','button');fileLabel.onkeydown=event=>{if(event.key==='Enter'||event.key===' '){event.preventDefault();fileLabel.querySelector('input[type=file]').click();}};}
$('settings').onsubmit=event=>{event.preventDefault();void apply(false);};$('generate').onclick=()=>void apply(true);
$('profile').addEventListener('change',()=>{$('inks').hidden=$('profile').value!=='palette';});
$('cancel').onclick=()=>{invalidate();message('Cancelled · previous work preserved');persist();};
$('family').onchange=()=>{invalidate();recipe=JSON.parse(loaded.bundle.examples[catalog.find(x=>x.id===$('family').value).recipe]);result=null;drafts={};navigation={zoom:1,x:0,y:0};remember();buildForm();display();persist();message('Starting recipe loaded · select Generate structure');};
for(const[id,offset]of[['undo',-1],['redo',1]])$(id).onclick=async()=>{
  invalidate();const token=epoch,target=cursor+offset;
  try{const entry=clone(history[target]);if(!entry)throw Error('No history entry in that direction');
    const validated=await run('validate',{'recipe.json':JSON.stringify(entry.recipe)},{},token);
    const accepted=await verifiedResult(entry.result,token);if(token!==epoch)return;
    cursor=target;recipe=entry.recipe;recipeDigest=jsonAsset(validated,'report.json').recipe_sha256;result=accepted;drafts={};buildForm();display();persist();message('History restored · instance validated');
    if(result&&!isCurrentResult())message('History restored · recipe changes need Generate structure');
  }catch(error){if(token===epoch)message('History could not be restored · current work preserved',error);}
};
$('border').onclick=()=>{const b=$('crop').value.split(',').map(Number),w=b[2]-b[0],h=b[3]-b[1];$('regions').value=pretty([{bounds:[b[0]+w*.2,b[1]+h*.2,b[2]-w*.2,b[3]-h*.2]}]);changed();};
$('fit').onclick=()=>{navigation={zoom:1,x:0,y:0};transform();persist();};
function zoom(factor){navigation.zoom=Math.max(.1,Math.min(20,navigation.zoom*factor));transform();persist();}
$('zoom-in').onclick=()=>zoom(1.25);$('zoom-out').onclick=()=>zoom(.8);$('overlays').onchange=drawOverlay;
$('canvas').onkeydown=event=>{if(['+','=','-','0','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key)){event.preventDefault();
  if(event.key==='+'||event.key==='=')zoom(1.25);else if(event.key==='-')zoom(.8);else if(event.key==='0')$('fit').click();
  else{navigation.x+=event.key==='ArrowLeft'?-20:event.key==='ArrowRight'?20:0;navigation.y+=event.key==='ArrowUp'?-20:event.key==='ArrowDown'?20:0;transform();persist();}}};
$('canvas').onpointerdown=event=>{if(event.button!==0)return;const world=worldPoint(event);if(!world)return;
  drag={x:event.clientX,y:event.clientY,world,nav:clone(navigation),tool:$('tool').value};
  if(drag.tool==='guide'){let distance=Infinity;for(const p of guidePoints()){const s=screenPoint(...p.point),d=Math.hypot(s[0]+$('canvas').getBoundingClientRect().left-event.clientX,s[1]+$('canvas').getBoundingClientRect().top-event.clientY);if(d<distance){drag.point=p;distance=d;}}if(distance>24){message('Choose a visible guide or scaffold point');drag=null;return;}}
  $('canvas').setPointerCapture(event.pointerId);};
$('canvas').onpointermove=event=>{if(!drag)return;if(drag.tool==='pan'){navigation.x=drag.nav.x+event.clientX-drag.x;navigation.y=drag.nav.y+event.clientY-drag.y;transform();}};
$('canvas').onpointerup=event=>{if(!drag)return;const p=worldPoint(event),start=drag;drag=null;
  try{if(start.tool==='region'&&p){const regions=JSON.parse($('regions').value);if(Math.abs(p.x-start.world.x)<.01||Math.abs(p.y-start.world.y)<.01)return;
    regions.push({bounds:[Math.min(p.x,start.world.x),Math.min(p.y,start.world.y),Math.max(p.x,start.world.x),Math.max(p.y,start.world.y)]});$('regions').value=pretty(regions);changed();}
    else if(start.tool==='guide'&&p){const field=inputEditors.get(start.point.kind).element,data=JSON.parse(field.value);
      if(start.point.kind==='scaffold')data.vertices[start.point.index].point=[p.x,p.y];else if(Array.isArray(data[start.point.index]))data[start.point.index]=[p.x,p.y];else Object.assign(data[start.point.index],{x:p.x,y:p.y});field.value=pretty(data);changed();}
    else persist();}catch(error){message('Edit needs correction',error);}};
$('canvas').onpointercancel=()=>{drag=null;};new ResizeObserver(transform).observe($('canvas'));
$('recipe-save').onclick=()=>download('pattern.recipe',JSON.stringify(recipe),'application/json');
$('save').onclick=()=>{const value=snapshot();value.result=encodedResult(value.result);value.history=[];download('florilegium-workspace.json',pretty(value),'application/json');};
for(const[id,name,type]of[['svg-save','pattern.svg','image/svg+xml'],['pdf-save','pattern.pdf','application/pdf'],['network-save','network.json','application/json']])$(id).onclick=()=>{if(!$(id).disabled&&result?.assets[name])download(name,result.assets[name],type);};
$('open').onchange=async()=>{invalidate();const token=epoch;try{await importWorkspace(await readFile($('open')),false,token);}catch(error){if(token===epoch){message('Import failed · previous work preserved',error);persist();}}finally{$('open').value='';}};
$('recipe-open').onchange=async()=>{invalidate();const token=epoch;try{const candidate=await readFile($('recipe-open'),2*1024*1024);if(token!==epoch)return;await run('validate',{'recipe.json':JSON.stringify(candidate)},{},token);
  recipe=candidate;result=null;drafts={};remember();buildForm();display();persist();message('Imported recipe validated · select Generate structure');}catch(error){if(token===epoch)message('Recipe import failed · previous work preserved',error);}finally{$('recipe-open').value='';}};
$('exemplar-open').onchange=async()=>{invalidate();const token=epoch;try{const data=await readFile($('exemplar-open'),2*1024*1024);if(token!==epoch)return;const library=Array.isArray(data)?data:data.design?.inputs?.library??data.library;
  if(!Array.isArray(library))throw Error('Import a library array or a DecoBrush recipe with inputs.library.');
  const edits=readEdits();edits.inputs.library=library;await run('validate',{'recipe.json':JSON.stringify(recipe)},{edits},token);
  inputEditors.get('library').element.value=pretty(library);changed();message('Exemplar library validated · generate to synthesize');
  }catch(error){if(token===epoch)message('Exemplar import failed · previous work preserved',error);}finally{$('exemplar-open').value='';}};
async function main(){try{
  loaded=await window.runtimeReady;catalog=JSON.parse(loaded.bundle.examples['catalog.json']).examples;
  const capabilities=jsonAsset(await run('capabilities',{}),'report.json');
  if(!catalog.every(row=>capabilities.families.includes(row.family)))throw Error('Recipe catalog does not match the actual capability registry');
  $('family').replaceChildren(...catalog.map(row=>new Option(title(row.id)+' · '+row.family,row.id)));$('family').disabled=false;
  recipe=JSON.parse(loaded.bundle.examples[catalog.find(x=>x.id==='periodic').recipe]);remember();buildForm();display();message('Local shared core ready · choose your structure');
  const restoreEpoch=epoch;
  try{const connection=await db(),saved=await new Promise((resolve,reject)=>{const request=connection.transaction('workspaces').objectStore('workspaces').get('current');request.onsuccess=()=>resolve(request.result);request.onerror=()=>reject(request.error);});
    if(saved&&restoreEpoch===epoch)await importWorkspace(saved,true,restoreEpoch);else if(!saved)persist();
  }catch(error){message('Saved workspace could not be restored · original saved copy retained',error);}
}catch(error){message('Runtime could not start · reload to retry',error);}}
// A read-only inspection surface supports reproducible browser acceptance receipts.
window.patternStudio={get state(){return{recipe:clone(recipe),result:clone(result),drafts:captureDrafts(),pending,epoch,history_length:history.length,cursor};},get saved(){return saveChain;}};
window.studioReady=main();
