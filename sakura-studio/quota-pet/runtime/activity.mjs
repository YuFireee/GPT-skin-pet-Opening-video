import {reduceDialogState,summarizeDialogState} from './dialog-state.mjs';
import {watch} from 'node:fs';
import {StringDecoder} from 'node:string_decoder';
import fs from 'node:fs/promises';import path from 'node:path';
export function createActivityReader({home,now=Date.now,maxFiles=128,budget=128*1024,cacheFile,watchChanges=false}={}){
 const files=new Map();const dirty=new Set();let watcher;
 const sessionsRoot=path.resolve(home,'sessions');
 if(watchChanges){try{watcher=watch(sessionsRoot,{recursive:true},(event,file)=>{
  if(typeof file!=='string'||!file.endsWith('.jsonl'))return;
  const resolved=path.resolve(sessionsRoot,file);if(!resolved.startsWith(sessionsRoot+path.sep))return;
  dirty.delete(resolved);dirty.add(resolved);while(dirty.size>32)dirty.delete(dirty.values().next().value);
 });watcher.on('error',()=>{watcher?.close();watcher=null});watcher.unref();}catch{}}
 async function includeChangedFiles(){
  for(const p of [...dirty].slice(-8)){
   if(files.has(p))continue;
   try{
    const actual=await fs.realpath(p),canonicalRoot=await fs.realpath(sessionsRoot);if(!actual.toLowerCase().startsWith(canonicalRoot.toLowerCase()+path.sep))continue;
    const stat=await fs.stat(p);if(!stat.isFile()||stat.mtimeMs<now()-7*86400000)continue;
    if(files.size>=maxFiles){excludedFiles++;continue;}
    files.set(p,{offset:0,partial:'',decoder:new StringDecoder('utf8'),tokens:0,days:{},buckets:{},minutes:{},baseline:stat.size>512*1024,start:Math.max(0,stat.size-512*1024),model:'unknown',bucketLimited:false,size:stat.size,birth:stat.birthtimeMs});
    const state=files.get(p);state.offset=state.start;if(state.start)state.tailLimited=true;
   }catch{}
  }
 }
 async function readDialogTails(hot){
  for(const [p,s] of hot.slice(0,2)){
   if(s.archived)continue;
   let handle;
   try{
    handle=await fs.open(p,'r');const stat=await handle.stat();
    if(s.dialogTailSize===stat.size&&s.dialogTailMtime===stat.mtimeMs)continue;
    const start=Math.max(0,stat.size-16384),data=Buffer.alloc(stat.size-start);
    await handle.read(data,0,data.length,start);
    const lines=data.toString('utf8').split('\n');if(start)lines.shift();lines.pop();
    for(const line of lines){try{s.dialog=reduceDialogState(s.dialog,JSON.parse(line),now())}catch{}}
    s.dialogTailSize=stat.size;s.dialogTailMtime=stat.mtimeMs;
   }catch{}finally{await handle?.close()}
  }
 }
let discovered=0,cursor=0,discoveryErrors=0,excludedFiles=0,cacheLoaded=false,cached=new Map(),savedAt=0;
 async function discover(){
  const cutoff=now()-7*86400000;const candidates=[];discoveryErrors=0;excludedFiles=0;const walk=async(dir,depth=0)=>{if(depth>5)return;let entries;try{entries=await fs.readdir(dir,{withFileTypes:true})}catch(error){if(error.code!=='ENOENT')discoveryErrors++;return}for(const e of entries){if(e.isSymbolicLink())continue;const p=path.join(dir,e.name);if(e.isDirectory())await walk(p,depth+1);else if(e.name.endsWith('.jsonl')){try{const st=await fs.stat(p);if(st.mtimeMs<cutoff)continue;if(candidates.length<maxFiles)candidates.push({p,mtime:st.mtimeMs,size:st.size,birth:st.birthtimeMs});else excludedFiles++}catch{discoveryErrors++}}}};
  // Local logs only; never reads auth.json or conversation message bodies into snapshots.
  await walk(path.join(home,'sessions'));await walk(path.join(home,'archived_sessions'));
  candidates.sort((a,b)=>b.mtime-a.mtime);const keep=new Set(candidates.slice(0,maxFiles).map(x=>x.p));for(const p of files.keys())if(!keep.has(p))files.delete(p);for(const p of keep)if(!files.has(p))files.set(p,{offset:0,partial:'',decoder:new StringDecoder('utf8'),tokens:0,days:{},buckets:{},minutes:{},baseline:false,start:0,model:"unknown",bucketLimited:false});
  for(const c of candidates){const item=files.get(c.p);if(item){const prior=cached.get(c.p);if(prior&&prior.birth===c.birth&&prior.offset<=c.size&&Number.isSafeInteger(prior.offset)&&prior.offset>=0){Object.assign(item,prior,{partial:'',decoder:new StringDecoder('utf8')});cached.delete(c.p)}if((!prior||prior.birth!==c.birth||prior.offset>c.size)&&item.offset===0&&c.size>512*1024){item.start=c.size-512*1024;item.offset=item.start;item.baseline=true;item.tailLimited=true;}item.birth=c.birth;item.size=c.size;item.error=false;item.archived=c.p.startsWith(path.resolve(home,'archived_sessions')+path.sep)}}discovered=now();
 }
 function consume(s,r){
  if(!s.archived)s.dialog=reduceDialogState(s.dialog,r,now());
  const p=r.payload??{},at=Date.parse(r.timestamp);if(r.type==='session_meta')return
  if(r.type==='turn_context'){if(typeof p.model==='string')s.model=p.model.slice(0,80);return}
  if(r.type==='token_usage_record'){r={...r,type:'event_msg',payload:{type:'token_count',info:{total_token_usage:p.thread_token_usage}}};return consume(s,r)}
  if(r.type!=='event_msg'&&r.type!=='response_item')return;
  if(p.type==='token_count'){const total=p.info?.total_token_usage?.total_tokens;if(Number.isSafeInteger(total)&&total>=0&&Number.isFinite(at)){const delta=s.baseline?0:Math.max(0,total-s.tokens);s.baseline=false;s.tokens=total;const boundary=new Date(now());boundary.setHours(0,0,0,0);boundary.setDate(boundary.getDate()-6);if(at<boundary.getTime()||at>now()+60000)return;const minute=Math.floor(at/60000)+'/'+s.model;if(delta>0)s.minutes[minute]=(s.minutes[minute]??0)+delta;const date=new Date(at);const day=[date.getFullYear(),String(date.getMonth()+1).padStart(2,'0'),String(date.getDate()).padStart(2,'0')].join('-');s.days[day]=(s.days[day]??0)+delta;const bucket=day+'/'+String(date.getHours()).padStart(2,'0')+'/'+s.model;if(delta>0&&(bucket in s.buckets||Object.keys(s.buckets).length<2048))s.buckets[bucket]=(s.buckets[bucket]??0)+delta;else if(delta>0)s.bucketLimited=true}return}

 }
 return {dispose(){watcher?.close();watcher=null;dirty.clear()},async read(){if(!cacheLoaded){cacheLoaded=true;if(cacheFile){try{const cache=JSON.parse(await fs.readFile(cacheFile,'utf8'));if(cache.version===4&&cache.home===path.resolve(home))cached=new Map(cache.files)}catch{}}}if(!discovered||now()-discovered>=60000)await discover();await includeChangedFiles();let left=budget;
  const entries=[...files],changed=[...dirty].reverse().map(p=>[p,files.get(p)]).filter(e=>e[1]),hot=[...new Map([...changed,...entries].map(e=>[e[0],e])).values()].slice(0,8),backlog=entries.slice(cursor).concat(entries.slice(0,cursor));const queue=[...new Map([...hot,...backlog].map(e=>[e[0],e])).values()];let opened=0;
  await readDialogTails(hot);
  dirty.clear();
  for(const [p,s] of queue){if(left<=0||opened>=8)break;const isHot=hot.some(([key])=>key===p);if(!isHot&&s.offset>=s.size)continue;opened++;cursor=(entries.findIndex(([key])=>key===p)+1)%Math.max(1,entries.length);let handle;try{handle=await fs.open(p,'r');const stat=await handle.stat();s.size=stat.size;s.error=false;if(stat.size<s.offset){Object.assign(s,{offset:0,partial:'',decoder:new StringDecoder('utf8'),tokens:0,days:{},buckets:{},minutes:{},baseline:false,start:0,model:"unknown",bucketLimited:false})}const size=Math.min(stat.size-s.offset,left,isHot?32768:65536);if(size<=0)continue;const b=Buffer.alloc(size);const {bytesRead}=await handle.read(b,0,size,s.offset);s.offset+=bytesRead;left-=bytesRead;const text=s.partial+s.decoder.write(b.subarray(0,bytesRead)),lines=text.split('\n');s.partial=lines.pop();if(s.partial.length>256*1024)s.partial='';for(const line of lines){try{consume(s,JSON.parse(line))}catch{}}}catch{s.error=true}finally{await handle?.close()}}
  const pending=entries.findIndex(([p,s])=>!hot.some(([key])=>key===p)&&s.offset<(s.size??0)&&!s.error);if(pending>=0)cursor=pending;
  const cutoffDay=new Date(now());cutoffDay.setHours(0,0,0,0);cutoffDay.setDate(cutoffDay.getDate()-6);const firstDay=[cutoffDay.getFullYear(),String(cutoffDay.getMonth()+1).padStart(2,'0'),String(cutoffDay.getDate()).padStart(2,'0')].join('-');const recentMinutes={};for(const s of files.values()){for(const key of Object.keys(s.days))if(key<firstDay)delete s.days[key];for(const key of Object.keys(s.buckets))if(key.slice(0,10)<firstDay)delete s.buckets[key];for(const [key,value] of Object.entries(s.minutes)){if(Number(key.split('/')[0])*60000<now()-5*3600000)delete s.minutes[key];else recentMinutes[key]=(recentMinutes[key]??0)+value}}
  const buckets={};for(const s of files.values())for(const [key,total] of Object.entries(s.buckets))buckets[key]=(buckets[key]??0)+total;
  const days={};for(const s of files.values())for(const [day,total] of Object.entries(s.days))days[day]=(days[day]??0)+total;
  if(cacheFile&&now()-savedAt>=60000){try{const checkpoint=[...files].map(([p,s])=>{const {decoder,partial,dialog,dialogTailSize,dialogTailMtime,...state}=s;const pending=decoder.lastNeed?decoder.lastTotal-decoder.lastNeed:0;return [p,{...state,offset:Math.max(0,s.offset-Buffer.byteLength(partial,'utf8')-pending)}]});await fs.writeFile(cacheFile+'.tmp',JSON.stringify({version:4,home:path.resolve(home),files:checkpoint}));await fs.rename(cacheFile+'.tmp',cacheFile);savedAt=now()}catch{}}
  const progress={files:files.size,readBytes:[...files.values()].reduce((a,s)=>a+Math.max(0,Math.min(s.offset,s.size??0)-(s.start??0)),0),totalBytes:[...files.values()].reduce((a,s)=>a+Math.max(0,(s.size??0)-(s.start??0)),0),errors:discoveryErrors+[...files.values()].filter(s=>s.error).length,excludedFiles};progress.complete=progress.readBytes>=progress.totalBytes&&!progress.errors&&!excludedFiles;
  return {checkedAt:now(),dialog:summarizeDialogState(files.values(),now()),progress,scope:'轻量模式：近7个自然日与约5小时；每份日志首次最多读取末尾512KiB。历史可能不完整，之后增量记录。',days,buckets,recentMinutes,tailLimited:[...files.values()].some(s=>s.tailLimited),bucketLimited:[...files.values()].some(s=>s.bucketLimited),files:files.size};
 }};
}
