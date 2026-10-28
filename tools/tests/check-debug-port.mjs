import assert from 'node:assert/strict';import fs from 'node:fs/promises';import path from 'node:path';import http from 'node:http';import {spawn} from 'node:child_process';
import {sourceRoot,reportsRoot} from './runtime.mjs';import {validDebugPort,freeDebugPort} from '../../sakura-studio/lib/debug-port.mjs';import {discover} from '../../sakura-studio/lib/cdp.mjs';
assert(validDebugPort(9335));for(const value of [0,80,65536,'9335',NaN])assert(!validDebugPort(value));
let wrong=false;const fake=http.createServer((req,res)=>res.end(JSON.stringify([{type:'page',url:'app://-/index.html',webSocketDebuggerUrl:`ws://127.0.0.1:${wrong?9335:fake.address().port}/fixture`}])));await new Promise(r=>fake.listen(0,'127.0.0.1',r));
try{assert((await discover(fake.address().port)).connected);wrong=true;assert(!(await discover(fake.address().port)).connected);}finally{await new Promise(r=>fake.close(r));}
assert(validDebugPort(await freeDebugPort()));
const root=path.join(reportsRoot,'debug-port-fixture-'+Date.now());await fs.cp(sourceRoot,root,{recursive:true,filter:p=>!path.relative(sourceRoot,p).split(path.sep).some(x=>['state','assets'].includes(x))&&!p.endsWith('.exe')});await fs.mkdir(path.join(root,'state'),{recursive:true});
await fs.writeFile(path.join(root,'native-bridge.ps1'),`param([string]$Action,[int]$DebugPort)
$file=Join-Path $PSScriptRoot 'state/launches.txt'
if($Action -eq 'Inspect'){@{owned=$false;reason='fixture inactive'}|ConvertTo-Json -Compress;exit}
if($Action -ne 'Launch'){throw 'Unexpected fixture action'}
[IO.File]::AppendAllText($file,([string]$DebugPort+"\n"))
$rows=[IO.File]::ReadAllLines($file)
$mode=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'state/mode.txt') -Raw
if($mode.Trim() -eq 'foreign'){@{started=$false;portOrphaned=$false;reason='foreign fixture owner'}|ConvertTo-Json -Compress;exit}
if($mode.Trim() -eq 'always-orphan' -or $rows.Length -eq 1){@{started=$false;portOrphaned=$true;reason='orphan fixture'}|ConvertTo-Json -Compress;exit}
@{started=$true;reused=$false}|ConvertTo-Json -Compress
`);await fs.writeFile(path.join(root,'state/mode.txt'),'once');
let child;
async function start(){let logs='';child=spawn(process.execPath,[path.join(root,'server.mjs')],{cwd:root,env:{...process.env,SAKURA_PORT:'0'},windowsHide:true,stdio:['ignore','pipe','pipe']});child.stdout.on('data',b=>logs+=b);child.stderr.on('data',b=>logs+=b);for(let i=0;i<100&&!logs.includes('SAKURA_STUDIO_URL=');i++)await new Promise(r=>setTimeout(r,50));const url=logs.match(/SAKURA_STUDIO_URL=(http:\/\/\S+)/)?.[1];assert(url,logs);const html=await(await fetch(url)).text(),token=html.match(/name="sakura-token" content="([^"]+)"/)[1];return ()=>fetch(url+'api/launch',{method:'POST',headers:{'X-Sakura-Token':token,'Content-Type':'application/json'},body:'{}'});}
const launches=async()=>(await fs.readFile(path.join(root,'state/launches.txt'),'utf8')).trim().split(/\s+/).map(Number);
try{
 let launch=await start();assert((await launch()).ok);let rows=await launches();assert.equal(rows.length,2);assert.equal(rows[0],9335);assert(validDebugPort(rows[1]));assert.notEqual(rows[1],rows[0]);assert.equal(JSON.parse(await fs.readFile(path.join(root,'state/debug-port.json'),'utf8')).port,rows[1]);
 const saved=rows[1];await new Promise(r=>{child.once('exit',r);child.kill();});launch=await start();assert((await launch()).ok);rows=await launches();assert.equal(rows.at(-1),saved,'Restart forgot the recovered debugging port');
 await fs.writeFile(path.join(root,'state/mode.txt'),'foreign');const before=rows.length;assert.equal((await launch()).status,409);assert.equal((await launches()).length,before+1,'Foreign owner caused a retry');
 await fs.writeFile(path.join(root,'state/mode.txt'),'always-orphan');const count=(await launches()).length;assert.equal((await launch()).status,409);assert.equal((await launches()).length,count+2,'Recovery retried more than once');
 console.log(JSON.stringify({passed:true,checks:['Custom loopback CDP port validated, foreign websocket port rejected','Orphaned port gets exactly one recovery attempt','Recovered port survives backend restart','Live foreign port owner is neither retried nor terminated','Repeated orphan conflicts stop after one retry'],scope:'Own mock bridge and HTTP fixtures; no real application launched or process terminated.'}));
}finally{if(child&&child.exitCode===null)child.kill();}
