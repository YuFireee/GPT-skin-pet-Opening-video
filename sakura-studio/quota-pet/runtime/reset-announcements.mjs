// Independent, read-only integration. Attribution required by the public API.
export const announcementSource='https://codex-resets.com';
const interval=30*60*1000,limit=64*1024;
function item(value,scheduled=false){
 if(!value||typeof value.id!=='string'||value.id.length>64||!['regular','banked'].includes(value.reset_type))return null;
 const at=Date.parse(value.announced_at);if(!Number.isFinite(at))return null;
 let url=announcementSource;
 try{const u=new URL(value.source?.url);if(u.protocol==='https:'&&['x.com','twitter.com','codex-resets.com'].includes(u.hostname)&&!u.username&&!u.password)url=u.href;}catch{}
 const scheduledFor=Date.parse(value.scheduled_for);
 return {id:value.id,kind:value.reset_type,at,text:String(value.text??'').slice(0,600),url,scheduled,
  scheduledFor:scheduled&&Number.isFinite(scheduledFor)?scheduledFor:null};
}
export function normalizeAnnouncements(body){
 if(body?.meta?.api_version!=='v1'||!body?.data)throw Error('Unsupported announcement format');
 return {latest:item(body.data.latest_reset),scheduled:item(body.data.scheduled_reset,true)};
}
export function createAnnouncementReader({read=()=>null,save=()=>{},fetcher=fetch,now=Date.now,timeoutMs=5000}={}){
 let cached=read()??{},busy=false;
 return {get busy(){return busy},snapshot:()=>cached,async tick({enabled=true,active=true}={}){
  const at=now();
  if(!enabled||!active||busy||(cached.nextCheckAt>at&&cached.nextCheckAt<=at+24*3600000))return;
  busy=true;const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeoutMs);
  let reader;
  try{
   const headers={Accept:'application/json'};if(typeof cached.etag==='string'&&cached.etag.length<256)headers['If-None-Match']=cached.etag;
   const response=await fetcher(announcementSource+'/api/v1/status',{headers,signal:controller.signal,redirect:'error'});
   if(response.status===304){cached={...cached,checkedAt:at,nextCheckAt:at+interval,error:null};}
   else {
    if(!response.ok){const retry=Number(response.headers.get('retry-after'));const error=Error('HTTP '+response.status);error.retry=Number.isFinite(retry)?Math.min(86400000,Math.max(interval,retry*1000)):interval;throw error;}
    if(Number(response.headers.get('content-length'))>limit)throw Error('Announcement response too large');
    reader=response.body.getReader();let size=0,chunks=[];
    for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>limit)throw Error('Announcement response too large');chunks.push(Buffer.from(part.value));}
    const data=normalizeAnnouncements(JSON.parse(Buffer.concat(chunks).toString('utf8')));
    cached={...data,source:announcementSource,checkedAt:at,nextCheckAt:at+interval,etag:response.headers.get('etag')?.slice(0,255)??null,error:null};
   }
  }catch(error){cached={...cached,source:announcementSource,nextCheckAt:at+(error.retry??interval),error:'公告读取失败，稍后再试；缓存不代表账户额度。'};}
  finally{clearTimeout(timer);try{await reader?.cancel();}catch{}busy=false;try{save(cached);}catch{}}
 }};
}
