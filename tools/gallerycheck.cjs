const fs=require('node:fs/promises'),path=require('node:path'),crypto=require('node:crypto');
const [url,playwright,out,executablePath]=process.argv.slice(2);
const {chromium}=require(playwright);
const sha=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const browser=await chromium.launch({headless:true,...(executablePath?{executablePath}:{})});
 const pages=[];await fs.mkdir(out,{recursive:true});
 try{
  for(const [label,width,height] of [['wide',1440,1000],['narrow',412,915]]){
   const page=await browser.newPage({viewport:{width,height}}),errors=[];
   page.on('pageerror',e=>errors.push(String(e)));page.on('response',r=>{if(r.status()>=400)errors.push(r.url()+':'+r.status());});
   await page.goto(url,{waitUntil:'load'});
   const checked=await page.evaluate(async()=>{
    const images=[...document.images];for(const image of images)image.loading='eager';
    await Promise.all(images.map(i=>i.decode()));
    return {images:images.length,decoded:images.filter(i=>i.complete&&i.naturalWidth>0).length,
            panels:document.querySelectorAll('article .pair').length,width:document.documentElement.scrollWidth};
   });
   if(errors.length||checked.images!==48||checked.decoded!==48||checked.panels!==22||checked.width>width)throw Error(JSON.stringify({errors,checked,width}));
   const files={};for(const [id,locator]of [['atlas',page.locator('header')],['collection',page.locator('#collection')],['micrography',page.locator('#micrography')]]){
    const b=await locator.screenshot({path:path.join(out,`${label}-${id}.png`)});files[id]=sha(b);
   }
   if(label==='wide'&&process.env.PATTERN_GALLERY_CAPTURE_ALL==='1'){
    for(const id of await page.locator('article').evaluateAll(items=>items.map(x=>x.id))){
     const b=await page.locator('#'+id).screenshot({path:path.join(out,'profile-'+id+'.png')});files[id]=sha(b);
    }
   }
   pages.push({label,viewport:{width,height},...checked,images_sha256:files});await page.close();
  }
  await fs.writeFile(path.join(out,'receipt.json'),JSON.stringify({schema_version:1,status:'passed',browser:browser.version(),pages},null,2)+'\n');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
