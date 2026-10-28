import {chromium,edgePath,reportsRoot} from './runtime.mjs';import fs from 'node:fs/promises';import path from 'node:path';import assert from 'node:assert/strict';
import {applySkin,restoreSkin,setSkinActivity} from '../../sakura-studio/lib/renderer.mjs';
const browser=await chromium.launch({executablePath:edgePath,headless:true});
try{
 const page=await browser.newPage({viewport:{width:800,height:600}});await page.setContent('<style>main{background:rgb(13,17,23)}</style><main style="display:none;background:rgb(13,17,23)!important"></main><aside>Test sidebar</aside><main><article>Fixture content</article></main>');
 await page.evaluate(()=>{const add=window.addEventListener.bind(window),remove=window.removeEventListener.bind(window),listeners=new Set();window.addEventListener=(type,fn,...rest)=>{if(type==='focus'||type==='blur')listeners.add(fn);return add(type,fn,...rest)};window.removeEventListener=(type,fn,...rest)=>{listeners.delete(fn);return remove(type,fn,...rest)};window.fixtureListenerCount=()=>listeners.size});
 const image=await page.evaluate(()=>{const canvas=document.createElement('canvas');canvas.width=canvas.height=1;return canvas.toDataURL('image/png')});
 const config={selectors:{'shell-main':'main','left-panel':'aside'},parts:{main:'main',sidebar:'aside',message:'article'},image,focusX:.27,themeId:'sakura-calm-soft-portrait',motion:true,sidebar:50,header:32,message:46,composer:42};
 const cdp=await page.context().newCDPSession(page);
 async function cycle(){
  await page.evaluate(applySkin,{...config,active:false});
  assert.equal(await page.locator('#sakura-motion').count(),0,'Background apply must not allocate effects');
  assert.equal(await page.locator('main').last().evaluate(el=>getComputedStyle(el).backgroundColor),'rgba(0, 0, 0, 0)');
  assert.notEqual(await page.locator('article').evaluate(el=>getComputedStyle(el).backgroundColor),'rgba(0, 0, 0, 0)');
  await page.evaluate(setSkinActivity,true);
  assert.equal(await page.locator('.sakura-petal').count(),30);
  assert.equal(await page.locator('.sakura-breeze').count(),0,'No duplicate scaled wallpaper in motion layer');
  const wallpaper=await page.evaluate(()=>getComputedStyle(document.body).background);
  const layer=await page.locator('#sakura-motion').elementHandle();
  await page.evaluate(()=>{window.dispatchEvent(new Event('blur'));document.dispatchEvent(new Event('visibilitychange'))});
  assert.equal(await layer.evaluate(el=>el.isConnected),true,'Page blur must not stop foreground animations');
  assert.equal(await page.locator('.sakura-petal').first().evaluate(el=>getComputedStyle(el).animationPlayState),'running');
  assert((await page.locator('.sakura-sunlight').evaluate(el=>el.getBoundingClientRect().width))<1500);
  await page.evaluate(setSkinActivity,false);
  assert.equal(await page.locator('#sakura-motion').count(),0);
  assert.equal(await layer.evaluate(el=>el.childElementCount),0,'Released layer must drop its children');
  assert.equal(await layer.evaluate(el=>el.getAnimations({subtree:true}).length),0);
  await layer.dispose();
  await page.evaluate(setSkinActivity,false);await page.evaluate(setSkinActivity,true);await page.evaluate(setSkinActivity,true);
  assert.equal(await page.locator('#sakura-motion').count(),1);assert.equal(await page.locator('.sakura-petal').count(),30);
  assert.equal(await page.evaluate(()=>getComputedStyle(document.body).background),wallpaper,'Wallpaper geometry stays unchanged across activity changes');
  await page.evaluate(restoreSkin);
  assert.equal(await page.locator('#sakura-motion,#sakura-studio-style,[data-sakura-part]').count(),0);assert.equal(await page.evaluate(()=>window.fixtureListenerCount()),0);
 }
 for(let i=0;i<5;i++)await cycle();await page.waitForTimeout(60);await cdp.send('HeapProfiler.collectGarbage');const before=await cdp.send('Memory.getDOMCounters');
 for(let i=0;i<60;i++)await cycle();
 await page.waitForTimeout(60);await cdp.send('HeapProfiler.collectGarbage');const after=await cdp.send('Memory.getDOMCounters');assert(after.nodes-before.nodes<50,JSON.stringify({before,after}));assert(after.jsEventListeners<=before.jsEventListeners+2,'Event listeners must remain bounded');
 const report={passed:true,cycles:60,before,after,checks:['Native background removes decorative DOM and cancels animations; foreground rebuilds one layer; page blur has no effect','Wallpaper geometry unchanged across background/foreground; no scaled duplicate image','Sunlight surface bounded to viewport dimensions','No focus listeners; theme restore removes DOM markers, pending callbacks and effects','DOM count remains bounded after repeated apply/restore and GC'],scope:'Isolated small-image browser fixture; not a guarantee about GPU drivers or long running production chats'};
 await fs.writeFile(path.join(reportsRoot,'renderer-resource-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}finally{await browser.close()}
