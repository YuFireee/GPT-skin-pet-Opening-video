import fs from 'node:fs/promises';import path from 'node:path';import {spawn} from 'node:child_process';import assert from 'node:assert/strict';import {sourceRoot,reportsRoot,projectRoot} from './runtime.mjs';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));const root=path.join(reportsRoot,'pet-resource-fixture');await fs.mkdir(root,{recursive:true});
const fixture=path.join(root,'host'),receipt=path.join(root,'pet'),data=path.join(root,'state'),app=path.join(root,'quota-pet');await fs.mkdir(data,{recursive:true});
for(const file of [fixture,fixture+'.stop',fixture+'.final',receipt,receipt+'.stop'])await fs.rm(file,{force:true});
const soakSeconds=Number(process.env.SAKURA_SOAK_SECONDS??180);
if(!Number.isFinite(soakSeconds)||soakSeconds<62||soakSeconds>600)throw Error('Soak range must be 62..600 seconds');
async function read(file,test=()=>true){for(let i=0;i<250;i++){try{const r=JSON.parse(await fs.readFile(file,'utf8'));if(test(r))return r}catch{}await sleep(100)}throw Error('Fixture receipt timeout')}
const host=spawn('powershell.exe',['-NoProfile','-STA','-File',path.join(projectRoot,'tools/tests/fit-test-host.ps1'),'-Receipt',fixture],{windowsHide:true,stdio:'ignore'});let pet;
try{
 const h=await read(fixture);await fs.cp(path.join(sourceRoot,'quota-pet'),app,{recursive:true});
 let code=(await fs.readFile(path.join(app,'widget.ps1'),'utf8')).replace(/^\uFEFF/,'');
 code=code.replace('$script:hostHandle=[GptWidgetNative]::FindCodex();','$script:hostHandle=[IntPtr]'+h.handle+';').replace('$script:foregroundHost=[GptWidgetNative]::ForegroundHost($foreground)','$script:foregroundHost=[IntPtr]::Zero');
 await fs.writeFile(path.join(app,'widget.ps1'),'\uFEFF'+code);
 await fs.writeFile(path.join(data,'settings.json'),JSON.stringify({layoutVersion:2,followHost:true,scale:.6,colorMode:'original',soundOn:false}));
 const config=path.join(root,'configuration.json');await fs.writeFile(config,JSON.stringify({appDir:app,dataDir:data,nodePath:process.execPath,codexPath:process.execPath,spriteFile:'sakura-soft-bust.png',themeId:'sakura-calm-soft-portrait',readinessMode:'native-window'}));
 pet=spawn('powershell.exe',['-NoProfile','-STA','-File',path.join(app,'widget.ps1'),'-ConfigurationPath',config,'-ReadyFile',receipt,'-ParentProcessId',String(process.pid)],{windowsHide:true,stdio:'ignore'});
 await read(receipt,r=>r.state==='ready');
 // A bounded idle soak, scoped to the isolated fixture. Its CLI
 // is the test Node executable, never the user's desktop app or account CLI.
 for(let elapsed=0;elapsed<soakSeconds;elapsed+=Math.min(30,soakSeconds-elapsed))await sleep(Math.min(30,soakSeconds-elapsed)*1000);
 const health=await read(path.join(data,'resource-health.json'),r=>r.samples?.length>=3);assert(health.samples.length<=60);assert(!health.paused);const values=health.samples.map(x=>x.privateMB);assert(Math.max(...values)<512);assert(values.at(-1)-values[0]<128,'Unexpected memory growth during isolated idle');
 await fs.writeFile(receipt+'.stop','stop');await read(receipt,r=>r.state==='closed');
 const report={passed:true,seconds:soakSeconds,privateMB:values,managedMB:health.samples.map(x=>x.managedMB),handles:health.samples.map(x=>x.handles),scope:'Isolated native WPF host with local test Node CLI; no real application launch or accessibility tree scan. A short soak does not prove absence of a long-term leak.'};await fs.writeFile(path.join(reportsRoot,'pet-resource-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}finally{if(pet?.exitCode===null){await fs.writeFile(receipt+'.stop','stop');await sleep(500);if(pet.exitCode===null)pet.kill()}await fs.writeFile(fixture+'.stop','stop');await sleep(200);if(host.exitCode===null)host.kill()}
