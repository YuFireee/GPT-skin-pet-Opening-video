import {createAnnouncementReader} from './reset-announcements.mjs';
import {evaluateQuotaAlerts} from './quota-alerts.mjs';
import os from 'node:os';
import {createActivityReader} from './activity.mjs';
import fs from 'node:fs';
import path from 'node:path';
import {readUsage,atomicJson,resolveCodexExecutable} from './usage.mjs';
import {createRefreshQueue,mergeUsageSnapshot,readRefreshRequest} from './refresh-queue.mjs';
import {acquireWorkerLock,processAlive,readJson} from './worker-state.mjs';
import {readPendingRequests,completeRequests,cleanRefreshResults,widgetUpdating,updatingSnapshot} from './refresh-client.mjs';

import {createPipeRefreshHandler} from './worker-ipc.mjs';

const config=readJson(process.argv[2]);
if(!config?.dataDir || !config?.codexPath)throw new Error('Invalid widget installation configuration');
if(widgetUpdating(config.dataDir))process.exit(0);
const parentPid=Number(process.argv[3]??0);
if(!Number.isSafeInteger(parentPid) || parentPid<0)throw new Error('Invalid parent process id');
let refresh,automaticPaused=false;
const ipc=createPipeRefreshHandler(()=>{automaticPaused=false;if(refresh)void refresh.request();});
const lock=await acquireWorkerLock(config.dataDir,parentPid,{onLost:()=>process.exit(1),onConnection:ipc.onConnection});
if(!lock)process.exit(0);
const activityReader=createActivityReader({home:process.env.CODEX_HOME||path.join(os.homedir(),'.codex'),watchChanges:true,cacheFile:path.join(config.dataDir,'activity-index.json')});
let activityBusy=false,activityAt=0;
const activityTick=async()=>{if(activityBusy)return;activityBusy=true;try{const snapshot=await activityReader.read();atomicJson(path.join(config.dataDir,'activity.json'),snapshot);atomicJson(path.join(config.dataDir,'dialog-state.json'),{...snapshot.dialog,checkedAt:snapshot.checkedAt});}catch{}finally{activityBusy=false;activityAt=Date.now()}};
const statusFile=path.join(config.dataDir,'status.json');
const healthFile=path.join(config.dataDir,'worker-status.json');
const announcementFile=path.join(config.dataDir,'reset-announcements.json');
const announcements=createAnnouncementReader({read:()=>readJson(announcementFile),save:data=>atomicJson(announcementFile,data)});
let announcementSettingsAt=0,announcementEnabled=true;
let status=null,requestToken=readRefreshRequest(path.join(config.dataDir,'refresh.flag')),lastActivity=Date.now(),heartbeat;
const activeRequestIds=new Set();
const initialStop=readRefreshRequest(path.join(config.dataDir,'stop.flag'));
const save=data=>{atomicJson(statusFile,data);status=data;
  if(data?.queryOk===true&&data.ok===true){try{const file=path.join(config.dataDir,'quota-alerts.json'),old=readJson(file),settings=readJson(path.join(config.dataDir,'settings.json'))??{},now=Date.now();const result=evaluateQuotaAlerts(old?.state,data,{now,enabled:settings.quotaAlertsOn!==false,threshold:settings.quotaAlertThreshold??20});if(result.state){const prior=old?.state?.accountKey===result.state.accountKey?(old.events??[]):[];atomicJson(file,{state:result.state,events:[...prior,...result.events].filter(e=>e.at>=now-300000&&e.at<=now+5000).slice(-12)})}}catch{}}
};
const health=()=>atomicJson(healthFile,{...lock.owner,at:Date.now(),busy:refresh.busy,lastRefresh:refresh.lastRefresh});
function exit() {
  clearInterval(heartbeat);
  activityReader.dispose();
  try{if(readJson(healthFile)?.token===lock.owner.token)fs.unlinkSync(healthFile);}catch{}
  try{lock.release();}catch{}
}
process.on('exit',exit);
process.on('SIGTERM',()=>process.exit(0));
process.on('SIGINT',()=>process.exit(0));
if(parentPid && !processAlive(parentPid))process.exit(0);
refresh=createRefreshQueue(async()=>{
  lastActivity=Date.now();
  const batch=readPendingRequests(config.dataDir);
  const pipeBatch=ipc.takeBatch();
  if(widgetUpdating(config.dataDir)){ipc.complete(pipeBatch,updatingSnapshot());completeRequests(config.dataDir,batch,updatingSnapshot());return;}
  for(const request of batch)activeRequestIds.add(request.id);
  try {
    const next=await readUsage(resolveCodexExecutable(config.codexPath),{onAccount:accountKey=>{
      if(status?.accountKey!==accountKey || !accountKey)save({ok:false,queryOk:false,accountKey,error:'正在读取当前账户额度…',windows:[],checkedAt:Date.now()});
    }});
    if(next.queryOk!==true){automaticPaused=true;if(!next.error?.includes('自动查询已暂停'))next.error=(next.error??'额度查询未完成')+'；自动查询已暂停，请手动刷新。';}
    save(mergeUsageSnapshot(status,next));
    ipc.complete(pipeBatch,status);
    completeRequests(config.dataDir,batch,status);
    lastActivity=Date.now();
  } catch(error) {
    automaticPaused=true;
    ipc.fail(pipeBatch);
    throw error;
  } finally {activeRequestIds.clear();}
},{onError:error=>{
  // A temporary filesystem failure must not stop the quota worker.
  const code=typeof error?.code==='string'?error.code:'IO';
  console.error('Quota snapshot could not be saved; next refresh will retry ('+code+').');
}});

// Persisted snapshots have not yet been matched to the current login.
save({ok:false,queryOk:false,error:'正在读取当前账户额度…',windows:[],checkedAt:Date.now()});
health();
if(parentPid)void refresh.request();
heartbeat=setInterval(()=>{
  if(Date.now()-activityAt>=5000)void activityTick();
  if(widgetUpdating(config.dataDir)){completeRequests(config.dataDir,readPendingRequests(config.dataDir),updatingSnapshot());ipc.complete(ipc.takeBatch(),updatingSnapshot());process.exit(0);}
  const stop=readRefreshRequest(path.join(config.dataDir,'stop.flag'));
  if((parentPid && (!processAlive(parentPid) || stop!==null)) || (stop!==null && stop!==initialStop))process.exit(0);
  // No background queries while Codex is not visible; a fresh query on return.
  const now=Date.now(),presence=readJson(path.join(config.dataDir,'presence.json'));
  const active=presence?.visible && now-presence.at>=0 && now-presence.at<5000 && processAlive(presence.pid);
  if(active)lastActivity=now;
  if(now-announcementSettingsAt>=5000){announcementSettingsAt=now;announcementEnabled=readJson(path.join(config.dataDir,'settings.json'))?.announcementsOn!==false;}
  void announcements.tick({enabled:announcementEnabled,active:!!active});
  const request=readRefreshRequest(path.join(config.dataDir,'refresh.flag'));
  const requested=request!==null && request!==requestToken;
  if(requested)requestToken=request;
  const pending=readPendingRequests(config.dataDir,now);
  if(requested){automaticPaused=false;void refresh.request();}
  else if(pending.some(request=>!activeRequestIds.has(request.id))){automaticPaused=false;void refresh.request();}
  else if(!automaticPaused && active && !refresh.busy && now-refresh.lastRefresh>=60000)void refresh.request();
  if(!parentPid && !active && !refresh.busy && pending.length===0 && ipc.pendingCount===0 && now-lastActivity>=30000)process.exit(0);
  cleanRefreshResults(config.dataDir,now);
  try{health();}catch{}
},1000);
