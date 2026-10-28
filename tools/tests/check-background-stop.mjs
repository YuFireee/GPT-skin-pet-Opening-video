import {sourceRoot,reportsRoot} from './runtime.mjs';import fs from 'node:fs/promises';import path from 'node:path';import {spawn} from 'node:child_process';import assert from 'node:assert/strict';
const sleep=ms=>new Promise(r=>setTimeout(r,ms)),dir=path.join(reportsRoot,'backend-resource-fixture');
await fs.mkdir(dir,{recursive:true});await fs.cp(sourceRoot,dir,{recursive:true,filter:p=>!path.relative(sourceRoot,p).split(path.sep).some(x=>['state','assets'].includes(x))&&!p.endsWith('.exe')});
await fs.mkdir(path.join(dir,'state'),{recursive:true});await fs.rm(path.join(dir,'state/probe-count.txt'),{force:true});await fs.writeFile(path.join(dir,'state/auto-theme.json'),'{"enabled":true}');
await fs.writeFile(path.join(dir,'native-bridge.ps1'),`param([string]$Action)\n$ErrorActionPreference='Stop'\nif($Action -ne 'Inspect'){throw 'Application launch forbidden in fixture'}\n[IO.File]::AppendAllText((Join-Path $PSScriptRoot 'state/probe-count.txt'),"probe\\n")\n@{owned=$false;connected=$false;reason='fixture unavailable'}|ConvertTo-Json -Compress\n`.replaceAll('\\n','\n'));
// An invalid executable exercises spawn-error cleanup. It cannot open a UI.
await fs.writeFile(path.join(dir,'SakuraBoot.exe'),'not an executable');
const server=spawn(process.execPath,[path.join(dir,'server.mjs')],{cwd:dir,env:{...process.env,SAKURA_PORT:'0'},windowsHide:true,stdio:['ignore','pipe','pipe']});let logs='';server.stdout.on('data',b=>logs+=b);server.stderr.on('data',b=>logs+=b);
try{
 for(let i=0;i<100&&!logs.includes('SAKURA_STUDIO_URL=');i++)await sleep(50);const base=logs.match(/SAKURA_STUDIO_URL=(http:\/\/[^\s]+)/)?.[1];assert(base,logs);const html=await(await fetch(base)).text(),token=html.match(/name="sakura-token" content="([^"]+)"/)[1];
 const api=(route,data)=>fetch(base+'api/'+route,{method:data?'POST':'GET',headers:{'X-Sakura-Token':token,'Content-Type':'application/json'},...(data?{body:JSON.stringify(data)}:{})});
 const responses=await Promise.all(Array.from({length:40},()=>api('status')));assert(responses.every(r=>r.ok));
 const count=async()=>{try{return (await fs.readFile(path.join(dir,'state/probe-count.txt'),'utf8')).trim().split(/\s+/).length}catch{return 0}};
 assert.equal(await count(),1,'Concurrent status polls must share one PowerShell inspection');
 await sleep(5500);assert.equal(JSON.parse(await fs.readFile(path.join(dir,'state/auto-theme.json'),'utf8')).enabled,false);const pausedCount=await count();await sleep(5100);assert.equal(await count(),pausedCount,'A failed automatic connection check must remain stopped');
 const failed=await api('boot-preview',{});assert(!failed.ok);const afterFailure=await count();await sleep(1800);assert((await count())<=afterFailure+1,'Failed visual spawn must stop its monitor');
 const report={passed:true,concurrentRequests:40,initialProbes:1,checks:['Concurrent status requests do not spawn a process per request','Unavailable application stops automatic monitoring','Invalid opening executable stops readiness polling; no UI or default application is invoked']};await fs.writeFile(path.join(reportsRoot,'background-stop-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}finally{if(server.exitCode===null)server.kill()}
