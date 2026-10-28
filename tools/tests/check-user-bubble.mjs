import {projectVersion} from './runtime.mjs';
import path from 'node:path';

import {projectRoot,sourceRoot,reportsRoot,chromium,edgePath} from './runtime.mjs';

import fs from 'node:fs/promises';import assert from 'node:assert/strict';import {applySkin,restoreSkin} from '../../sakura-studio/lib/renderer.mjs';



const browser=await chromium.launch({executablePath:edgePath,headless:true});

try{

 const page=await browser.newPage();await page.setContent('<style>.bubble{background:rgb(80,60,90);border-radius:20px;padding:10px 16px}.wrap{padding:0;margin:0}</style><aside></aside><main><article id="user" class="wrap" data-local-conversation-user-anchor><div class="bubble" data-message-author-role="user">Example</div></article><article id="assistant" data-message-author-role="assistant">Reply</article></main>');

 const snapshot=()=>{const e=document.querySelector('.bubble'),s=getComputedStyle(e);return {background:s.backgroundColor,padding:s.padding,radius:s.borderRadius,width:e.getBoundingClientRect().width}};

 const before=await page.evaluate(snapshot);const image='data:image/png;base64,'+(await fs.readFile('sakura-studio/assets/sakura-calm-soft-portrait.png')).toString('base64');

 const selectors={'shell-main':'main','left-panel':'aside'},parts={main:'main',sidebar:'aside',message:'[data-message-author-role], [data-local-conversation-user-anchor]'};

 await page.evaluate(applySkin,{selectors,parts,image,focusX:.27,themeId:'sakura-calm-soft-portrait',motion:false,message:46,sidebar:50,header:32,composer:42});

 assert.deepEqual(await page.evaluate(snapshot),before);

 assert.equal(await page.locator('#user').getAttribute('data-sakura-part'),'user-message');assert.equal(await page.locator('#user').evaluate(e=>getComputedStyle(e).backgroundColor),'rgba(0, 0, 0, 0)');

 assert.equal(await page.locator('#assistant').getAttribute('data-sakura-part'),'message');assert.notEqual(await page.locator('#assistant').evaluate(e=>getComputedStyle(e).backgroundColor),'rgba(0, 0, 0, 0)');

 await page.evaluate(()=>document.querySelector('main').insertAdjacentHTML('beforeend','<article id="later" data-message-author-role="user"><div class="bubble">New</div></article>'));await page.waitForFunction(()=>document.querySelector('#later').getAttribute('data-sakura-part')==='user-message');

 await page.evaluate(restoreSkin);assert.equal(await page.locator('[data-sakura-part]').count(),0);assert.deepEqual(await page.evaluate(snapshot),before);

 const report={version:projectVersion,passed:true,checks:['User outer card remains transparent and native bubble dimensions/colors stay unchanged','Assistant reading card remains styled','Newly inserted user messages are classified correctly','Restore removes theme attributes']};await fs.writeFile(path.join(reportsRoot,'user-bubble-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));

}finally{await browser.close()}

