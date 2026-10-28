import {projectRoot,sourceRoot,reportsRoot} from './runtime.mjs';import fs from 'node:fs/promises';import path from 'node:path';import {spawn} from 'node:child_process';import assert from 'node:assert/strict';
import {writeBootSignals} from '../../sakura-studio/lib/boot-monitor.mjs';
const dir=path.join(reportsRoot,'raw-replacement');await fs.mkdir(dir,{recursive:true});const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function read(file,p=()=>true){for(let i=0;i<350;i++){try{const result=JSON.parse(await fs.readFile(file,'utf8'));if(p(result))return result}catch{}await sleep(60)}throw Error('Receipt timeout '+file)}
const firstFile=path.join(dir,'first-'+Date.now()),secondFile=path.join(dir,'second-'+Date.now());
function host(file,width){return spawn('powershell.exe',['-NoProfile','-STA','-File',path.join(projectRoot,'tools/tests/fit-test-host.ps1'),'-Receipt',file,'-Width',String(width),'-Height','700'],{windowsHide:true,stdio:'ignore'})}
const first=host(firstFile,1000),second=host(secondFile,1400);let boot;
try{
 const a=await read(firstFile),b=await read(secondFile),receipt=path.join(dir,'opening-'+Date.now());await writeBootSignals(receipt,a,false);
 boot=spawn(path.join(sourceRoot,'SakuraBoot.exe'),['Boot',path.join(sourceRoot,'assets/sakura-calm-soft-portrait.png'),receipt,'--video',path.join(sourceRoot,'assets/sakura-opening.mp4'),'--handoff','--background-main'],{windowsHide:true,stdio:'ignore'});
 const initial=await read(receipt,r=>r.mediaState==='playing'&&r.backgroundHeld);await fs.writeFile(firstFile+'.stop','stop');await read(firstFile+'.final');
 await writeBootSignals(receipt,b,false);const changed=await read(receipt,r=>r.sourceGeneration>initial.sourceGeneration&&r.backgroundHeld&&r.mediaState==='playing');assert.equal(changed.skipEnabled,false);
 await writeBootSignals(receipt,b,true);const final=await read(receipt,r=>r.state==='closed');assert.equal(final.handoff,'live-window');assert.equal(final.reason,'completed');assert.equal(final.skipHintVisible,false);assert.equal(final.skipEnabled,false);
 for(const key of ['left','top','width','height'])assert(Math.abs(final[key]-b.client[key])<1,key);
 const report={version:'0.9.0',passed:true,checks:['Closed main window is replaced during playback without reusing stale native state','New source remains in background before readiness','Natural completion hands off to the replacement window','Closed receipts no longer claim a visible skip hint'],initialGeneration:initial.sourceGeneration,finalGeneration:final.sourceGeneration};await fs.writeFile(path.join(reportsRoot,'window-replacement-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}finally{if(boot?.exitCode===null)boot.kill();for(const file of [firstFile,secondFile])await fs.writeFile(file+'.stop','stop');await sleep(300);if(first.exitCode===null)first.kill();if(second.exitCode===null)second.kill()}
