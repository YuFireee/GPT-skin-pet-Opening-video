import {projectVersion} from './runtime.mjs';
import path from 'node:path';

import {projectRoot,sourceRoot,reportsRoot,chromium,edgePath} from './runtime.mjs';

import assert from 'node:assert/strict';import fs from 'node:fs/promises';

import {bootDesktopReady,bootShellStatus} from '../../sakura-studio/lib/boot-readiness.mjs';



const browser=await chromium.launch({executablePath:edgePath,headless:true});

try{

 const page=await browser.newPage();await page.setContent('<aside style="width:200px;height:600px"></aside><main style="display:none"></main><main style="width:800px;height:600px"></main>');

 await page.evaluate(()=>Object.defineProperty(document,'visibilityState',{get:()=> 'hidden',configurable:true}));

 const selectors={'shell-main':'main','left-panel':'aside'};

 const shell=await page.evaluate(bootShellStatus,selectors);const c={owned:true,connected:true,window:{visible:true,minimized:false}};

 assert.equal(await page.evaluate(()=>document.visibilityState),'hidden');assert(bootDesktopReady(c,shell),'Occluded rendered source must release the opening');

 assert(!bootDesktopReady({...c,owned:false},shell));assert(!bootDesktopReady({...c,connected:false},shell));assert(!bootDesktopReady({...c,window:{visible:false,minimized:false}},shell));assert(!bootDesktopReady({...c,window:{visible:true,minimized:true}},shell));

 await page.locator('main').last().evaluate(el=>el.style.display='none');assert(!bootDesktopReady(c,await page.evaluate(bootShellStatus,selectors)));

 await page.locator('main').last().evaluate(el=>el.style.display='block');await page.locator('aside').evaluate(el=>el.remove());assert(!bootDesktopReady(c,await page.evaluate(bootShellStatus,selectors)));

 const report={version:projectVersion,passed:true,checks:['Rendered native window can be ready while Chromium visibilityState is hidden by the opening and its first matching main is an unmounted route','Hidden, minimized, disconnected and unowned windows stay waiting','Incomplete or collapsed shell stays waiting']};await fs.writeFile(path.join(reportsRoot,'occluded-readiness-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));

}finally{await browser.close()}

