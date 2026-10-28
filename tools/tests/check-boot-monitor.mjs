import {projectVersion} from './runtime.mjs';
import {projectRoot,reportsRoot} from './runtime.mjs';import fs from 'node:fs/promises';import path from 'node:path';import assert from 'node:assert/strict';

import {watchBootReadiness,writeBootSignals} from '../../sakura-studio/lib/boot-monitor.mjs';

const file=path.join(reportsRoot,'.monitor-fixture');let index=0;

const old={handle:101,pid:11,visible:true,minimized:true},next={handle:202,pid:22,visible:true,minimized:true};

const states=[{connected:false},{owned:true,connected:true,window:old,ready:true},{owned:true,connected:true,window:old,ready:false},{owned:true,connected:true,window:next,ready:true},{error:true},{owned:false,connected:true,window:next,ready:true}];

const seen=[];await watchBootReadiness({active:()=>index<states.length,inspect:async()=>{const state=states[index];if(state.error)throw Error('Renderer restarted');return state;},shell:async c=>({ready:c.ready}),publish:async(target,ready)=>{await writeBootSignals(file,target,ready);seen.push({target:await fs.readFile(file+'.target','utf8').catch(()=>null),ready:await fs.access(file+'.desktop-ready').then(()=>true,()=>false)});},sleep:async()=>{index++;}});

assert.deepEqual(seen,[{target:null,ready:false},{target:'101 11',ready:true},{target:'101 11',ready:false},{target:'202 22',ready:true},{target:null,ready:false},{target:null,ready:false}]);

for(const suffix of ['.target','.target.tmp','.desktop-ready'])await fs.rm(file+suffix,{force:true});

const report={version:projectVersion,passed:true,checks:['Readiness is revoked when a prepared shell disappears','Recreated main window replaces the old native target','Inspection failures and unowned connections revoke skip permission','Target updates use a complete file replacement']};await fs.writeFile(path.join(reportsRoot,'boot-monitor-checks.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));

