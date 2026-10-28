import http from 'node:http';import fs from 'node:fs/promises';import path from 'node:path';import {spawn} from 'node:child_process';import {createHash} from 'node:crypto';import assert from 'node:assert/strict';
import {sourceRoot,reportsRoot} from './runtime.mjs';
const missingPreview=process.argv.includes('--without-preview');
const appRoot=missingPreview?path.join(reportsRoot,'native-control-no-preview'):sourceRoot;
if(missingPreview){await fs.mkdir(appRoot,{recursive:true});await fs.copyFile(path.join(sourceRoot,'SakuraControl.exe'),path.join(appRoot,'SakuraControl.exe'));}
const receipt=path.join(reportsRoot,missingPreview?'native-control-missing-preview.json':'native-control-checks.json');await fs.rm(receipt,{force:true});
const installationId=createHash('sha256').update(appRoot.toLowerCase()).digest('hex');let running=false,duplicate;const calls=[];
const settings={themeId:'sakura-calm-soft-portrait',petId:'sakura-calm-soft-portrait',sidebar:50,rail:35,header:32,menubar:12,message:46,composer:42,motion:true,boot:false,bootSound:true,companion:false};
const server=http.createServer(async(req,res)=>{
 calls.push({url:req.url,method:req.method,at:Date.now()});res.setHeader('Content-Type','application/json; charset=utf-8');
 if(req.url==='/health')return res.end(JSON.stringify({service:'sakura-studio',installationId}));
 if(req.url==='/'){res.setHeader('Content-Type','text/html');return res.end('<meta name="sakura-token" content="fixture-only-token">')}
 assert.equal(req.headers['x-sakura-token'],'fixture-only-token');
 if(req.url==='/api/control-state'){
  if(!duplicate){duplicate=true;setTimeout(()=>{duplicate=spawn(path.join(appRoot,'SakuraControl.exe'),['--show','--port',String(server.address().port)],{windowsHide:true,stdio:'ignore'})},100)}
  return res.end(JSON.stringify({settings,companionRunning:running,autoTheme:{enabled:false},workspace:{state:'idle'}}));
 }
 if(req.url==='/api/companion'&&req.method==='POST'){let raw='';for await(const part of req)raw+=part;running=JSON.parse(raw).enabled;return res.end(JSON.stringify({running}))}
 res.statusCode=404;res.end('{}');
});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const child=spawn(path.join(appRoot,'SakuraControl.exe'),['--port',String(server.address().port),'--parent',String(process.pid),'--smoke-test',receipt],{windowsHide:true,stdio:'ignore'});
try{
 let timeout;const exit=await Promise.race([new Promise(resolve=>child.once('exit',code=>resolve({code}))),new Promise(resolve=>timeout=setTimeout(()=>resolve({timeout:true}),20000))]);clearTimeout(timeout);assert(!exit.timeout,'Native control fixture timeout');assert.equal(exit.code,0);
 const report=JSON.parse((await fs.readFile(receipt,'utf8')).replace(/^\uFEFF/,''));assert(report.passed,report.error);assert(report.closedWindowReleased);assert.equal(report.hiddenPolling,false);
 assert.equal(report.previewLoaded,!missingPreview);assert(report.previewFileUnlocked);assert(report.cycleGdiGrowth<=8);
 assert.equal(calls.filter(c=>c.url==='/api/companion').length,2);assert(!calls.some(c=>['/api/launch','/api/status','/api/workspace/start'].includes(c.url)),'UI opening must not launch/inspect application');
 assert(Date.now()-calls.at(-1).at>=1100,'Hidden tray continued polling');
 report.scope='Isolated fake local service and own native control window; 30 window open/close cycles, preview file unlocking and disposal, two pet actions, no real application or account CLI launched. Short idle sample is not long-term performance proof.';report.requestCount=calls.length;
 await fs.writeFile(receipt,JSON.stringify(report,null,2));console.log(JSON.stringify(report));
 // A tray-only controller must leave when its backend exits, without polling or API calls.
 const parent=spawn(process.execPath,['-e','setTimeout(()=>{},900)'],{windowsHide:true,stdio:'ignore'});const before=calls.length;
 const tray=spawn(path.join(appRoot,'SakuraControl.exe'),['--port',String(server.address().port),'--parent',String(parent.pid)],{windowsHide:true,stdio:'ignore'});
 let guard;try{const result=await Promise.race([new Promise(resolve=>tray.once('exit',code=>resolve(code))),new Promise(resolve=>guard=setTimeout(()=>resolve('timeout'),4000))]);assert.equal(result,0,'Tray did not exit with backend');assert.equal(calls.length,before,'Hidden tray queried backend');}finally{clearTimeout(guard);if(tray.exitCode===null)tray.kill();if(parent.exitCode===null)parent.kill()}
}finally{if(child.exitCode===null)child.kill();if(duplicate?.pid&&duplicate.exitCode===null)duplicate.kill();await new Promise(resolve=>server.close(resolve))}
