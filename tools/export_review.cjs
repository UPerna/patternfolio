/* Rasterize the real SVG bytes with the browser, retaining alpha and backdrops. */
const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const {chromium}=require(process.env.PATTERN_PLAYWRIGHT||'playwright');
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const root=path.resolve(process.argv[2]),out=path.resolve(process.argv[3]||root);const review=JSON.parse(await fs.readFile(path.join(root,'export-review.json'),'utf8'));
 const browser=await chromium.launch({headless:true,...(process.env.PATTERN_BROWSER?{executablePath:process.env.PATTERN_BROWSER}:{})});
 try{
 const page=await browser.newPage();const rows=[];await fs.mkdir(path.join(out,'raster'),{recursive:true});
 for(const row of review.profiles){
  const folder=path.join(root,row.folder),view=JSON.parse(await fs.readFile(path.join(folder,'view.json'),'utf8'));
  const outputs={};
  for(const name of ['pattern','diagnostic','monochrome','crop']){
   const source=await fs.readFile(path.join(folder,name+'.svg'),'utf8');
   if(name!=='pattern'&&sha(source)!==row.outputs[name+'.svg'])throw Error(row.id+'/'+name+' SVG digest mismatch');
   const result=await page.evaluate(async({source,bounds,regions,name})=>{
    const image=new Image();image.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(source)));await image.decode();
    const w=800,h=Math.max(1,Math.round(w*image.naturalHeight/image.naturalWidth));
    const canvas=document.createElement('canvas');canvas.width=w;canvas.height=h;const ctx=canvas.getContext('2d',{willReadFrequently:true});ctx.drawImage(image,0,0,w,h);
    const data=ctx.getImageData(0,0,w,h).data;let painted=0,partial=0,clear=0,nonneutral=0,protectedSamples=0,protectedInk=0,alphaDifferences=0;
    if(name==='pattern')window.cleanAlpha=data;
    for(let i=0;i<data.length;i+=4){if(data[i+3]===0)clear++;else{painted++;if(data[i+3]<255)partial++;if(name==='monochrome'&&Math.max(data[i],data[i+1],data[i+2])-Math.min(data[i],data[i+1],data[i+2])>1)nonneutral++;}if(name==='monochrome'&&data[i+3]!==window.cleanAlpha[i+3])alphaDifferences++;}
    if(name!=='crop')for(const region of regions){const b=region.bounds;
     const x0=Math.max(0,Math.ceil((b[0]-bounds[0])/(bounds[2]-bounds[0])*w)+2),x1=Math.min(w,Math.floor((b[2]-bounds[0])/(bounds[2]-bounds[0])*w)-2);
     const y0=Math.max(0,Math.ceil((bounds[3]-b[3])/(bounds[3]-bounds[1])*h)+2),y1=Math.min(h,Math.floor((bounds[3]-b[1])/(bounds[3]-bounds[1])*h)-2);
     for(let y=y0;y<y1;y++)for(let x=x0;x<x1;x++){protectedSamples++;if(data[(y*w+x)*4+3])protectedInk++;}
    }
    const transparent=canvas.toDataURL('image/png').split(',')[1];
    ctx.globalCompositeOperation='destination-over';ctx.fillStyle='#e6d5b7';ctx.fillRect(0,0,w,h);const colored=canvas.toDataURL('image/png').split(',')[1];
    return{width:w,height:h,painted,partial,clear,nonneutral,protectedSamples,protectedInk,alphaDifferences,transparent,colored};
   },{source,bounds:view.crop,regions:view.protected_regions,name});
   if(result.protectedInk!==0)throw Error(row.id+'/'+name+' paints protected interior');
   if(name==='pattern'&&!result.painted)throw Error(row.id+' blank');
   if(name==='monochrome'&&(result.nonneutral!==0||result.alphaDifferences!==0))throw Error(row.id+' monochrome changes alpha coverage or has chroma');
   const hashes={};for(const kind of ['transparent','colored']){const bytes=Buffer.from(result[kind],'base64');await fs.writeFile(path.join(out,'raster',row.id+'-'+name+'-'+kind+'.png'),bytes);hashes[kind]=sha(bytes);delete result[kind];}
   outputs[name]={source_sha256:sha(source),...result,png_sha256:hashes};
  }
  rows.push({id:row.id,outputs});console.log('SVG alpha/background review',row.id);
 }
 if(!rows.some(r=>r.outputs.pattern.protectedSamples>0&&r.outputs.pattern.clear>0))throw Error('Protected interior test had no clear samples');
 await fs.writeFile(path.join(out,'browser-export-review.json'),JSON.stringify({schema_version:1,status:'alpha_monochrome_protected_checks_passed_visual_pending',browser:browser.version(),tool_sha256:sha(await fs.readFile(__filename)),profiles:rows},null,2)+'\n');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
