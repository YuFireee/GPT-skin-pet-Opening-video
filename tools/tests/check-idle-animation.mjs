import fs from 'node:fs/promises';import path from 'node:path';import http from 'node:http';import assert from 'node:assert/strict';
import {chromium,edgePath,reportsRoot,projectRoot} from './runtime.mjs';
const variant=process.argv[2]||'soft-portrait-idle-v1';assert.match(variant,/^soft-portrait-(idle-v1|running-v[23456]|confirmation-v[123])$/);
const folder=path.join(projectRoot,'local-only-materials/sakura-studio/pet/animations',variant);
const label=variant.includes('confirmation')?'confirmation':variant.includes('running')?'executing':'idle';
const timing=JSON.parse(await fs.readFile(path.join(folder,'frames/timing.json'),'utf8'));
assert.equal(timing.fixedChannelChecks,timing.fixedChannelsEqual);if(['soft-portrait-running-v3','soft-portrait-running-v4'].includes(variant)){assert(timing.jawChannelChecks>0);assert.equal(timing.jawChannelChecks,timing.jawChannelsEqual);}const frameCount=variant==='soft-portrait-running-v6'?43:27;assert.equal(timing.durationsMs.length,frameCount);if(['soft-portrait-running-v5','soft-portrait-running-v6','soft-portrait-confirmation-v1','soft-portrait-confirmation-v2','soft-portrait-confirmation-v3'].includes(variant)){assert(timing.staticArmChannelChecks>0);assert.equal(timing.staticArmChannelChecks,timing.staticArmChannelsEqual);assert.equal(timing.bodyChannelChecks,timing.bodyChannelsEqual);}
if(['soft-portrait-confirmation-v2','soft-portrait-confirmation-v3'].includes(variant)){assert.equal(timing.faceOverlapPixels,0);assert.equal(timing.chinOverlapPixels,0);}
const server=http.createServer(async(req,res)=>{const name=req.url==='/preview.gif'?'idle-preview.gif':req.url==='/preview.apng'?'idle.apng':null;if(!name){res.writeHead(404).end();return}res.setHeader('Access-Control-Allow-Origin','*');res.setHeader('Content-Type',name.endsWith('gif')?'image/gif':'image/png');res.end(await fs.readFile(path.join(folder,name)))});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const base='http://127.0.0.1:'+server.address().port;
const browser=await chromium.launch({executablePath:edgePath,headless:true});
try{
 const page=await browser.newPage({viewport:{width:512,height:512}});
 await page.setContent('<style>body{margin:0;background:#efe7f4}img{width:512px;height:512px}</style><img alt="idle preview">');
 await page.locator('img').evaluate((img,src)=>new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.crossOrigin="anonymous";img.src=src}),base+'/preview.gif');
 const metadata=await page.locator('img').evaluate(img=>{const c=document.createElement('canvas');c.width=c.height=512;const ctx=c.getContext('2d');ctx.drawImage(img,0,0);return {width:img.naturalWidth,height:img.naturalHeight,alpha:ctx.getImageData(0,0,1,1).data[3]}});
 assert.deepEqual(metadata,{width:512,height:512,alpha:0});
 await page.screenshot({path:path.join(reportsRoot,label+'-preview-open.png')});await page.waitForTimeout(3590);await page.screenshot({path:path.join(reportsRoot,label+'-preview-blink.png')});
 await page.locator('img').evaluate((img,src)=>new Promise((resolve,reject)=>{img.onload=resolve;img.onerror=reject;img.crossOrigin="anonymous";img.src=src}),base+'/preview.apng');
 assert.equal(await page.locator('img').evaluate(img=>img.naturalWidth),512);
 const report={passed:true,frames:frameCount,width:512,height:512,durationMs:timing.durationsMs.reduce((a,b)=>a+b,0),transparent:true,fixedChannelsVerified:timing.fixedChannelChecks,scope:'Generated role material preview and decoding only; not a desktop runtime performance test.'};await fs.writeFile(path.join(reportsRoot,label+'-animation-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
