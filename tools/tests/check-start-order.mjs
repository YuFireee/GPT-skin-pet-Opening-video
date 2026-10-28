import path from 'node:path';
import {projectRoot,sourceRoot,reportsRoot} from './runtime.mjs';
import assert from 'node:assert/strict';import fs from 'node:fs/promises';
import {createWorkspaceController} from '../../sakura-studio/lib/workspace.mjs';
const pause=()=>new Promise(r=>setTimeout(r,5));async function finish(c){for(let i=0;i<200;i++){if(c.snapshot().state!=='running')return c.snapshot();await pause()}throw Error('job timeout')}
const config={themeId:'sakura-calm-soft-portrait',boot:true,companion:false};
const base={connection:async()=>({connected:true,window:{visible:true}}),launch:async()=>({started:true}),apply:async c=>({verification:{rendered:true,themeId:c.themeId},window:{pageVisible:true,foreground:true}}),ensureCompanion:async()=>{}};
const checks=[];
{
 const events=[];let display,complete;
 const c=createWorkspaceController({...base,beginBoot:()=>new Promise(r=>{display=()=>{events.push('opening-visible');r({finished:new Promise(done=>complete=done),stop:async()=>events.push('opening-stopped')})}}),connection:async()=>{events.push('inspect');return {connected:false,window:null}},launch:async()=>{events.push('launch');return {started:true}},apply:async cfg=>{events.push('apply');return base.apply(cfg)}});
 // Connection becomes available only after launch, without delaying the opening.
 const job=c.start(config);await pause();assert.deepEqual(events,[]);display();await pause();assert.deepEqual(events,['opening-visible','inspect','launch']);assert.equal(c.snapshot().state,'running');
 complete();
 // Use a short synthetic deadline: the order assertion above is the concern here.
 c.cancel(job.id);await finish(c);assert(events.includes('opening-stopped'));checks.push('Visible opening precedes inspection and application launch; cancellation cleans up opening');
}
{
 let stopped=false;
 const c=createWorkspaceController({...base,beginBoot:async()=>({finished:Promise.resolve(),stop:async()=>{stopped=true}}),connection:async()=>({connected:false,window:null}),launch:async()=>({started:false,reason:'test launch error'})});c.start(config);assert.equal((await finish(c)).state,'failed');assert(stopped);checks.push('Launch failure closes its opening instead of leaving a waiting window');
}
{
 let begin=0;const c=createWorkspaceController({...base,beginBoot:async()=>{begin++;throw Error('opening unavailable')}});c.start(config);assert.equal((await finish(c)).state,'partial');assert.equal(begin,1);checks.push('Opening failure still permits theme launch with a visible warning');
 const d=createWorkspaceController({...base,beginBoot:async()=>{throw Error('must not run')}});d.start({...config,boot:false});assert.equal((await finish(d)).state,'succeeded');checks.push('Disabled opening retains normal launch');
}
const report={version:'0.9.0',passed:true,checks};await fs.writeFile(path.join(reportsRoot,'start-order-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
