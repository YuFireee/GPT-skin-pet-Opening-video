export function evaluateQuotaAlerts(previous,snapshot,{now=Date.now(),enabled=true,threshold=20}={}){
 const valid=snapshot?.ok===true&&snapshot.queryOk===true&&typeof snapshot.accountKey==='string'&&snapshot.accountKey&&Number.isFinite(snapshot.observedAt)&&now-snapshot.observedAt>=-5000&&now-snapshot.observedAt<=180000;
 if(!valid)return {state:previous??null,events:[]};
 threshold=Math.max(1,Math.min(50,Number(threshold)||20));
 const state=previous?.accountKey===snapshot.accountKey&&previous.windows&&typeof previous.windows==='object'&&Number.isFinite(previous.observedAt)&&previous.observedAt<=now+5000?structuredClone(previous):{accountKey:snapshot.accountKey,observedAt:0,windows:{}};
 if(snapshot.observedAt<=state.observedAt)return {state,events:[]};
 const events=[],next={};
 for(const window of (snapshot.windows??[]).slice(0,16)){
  const remaining=window?.remaining,reset=window?.resetsAt;
  if(typeof remaining!=='number'||!Number.isFinite(remaining)||remaining<0||remaining>100)continue;
  const key=String(window.kind??'timed')+':'+String(window.minutes??'unknown');
  const old=state.windows[key],seconds=snapshot.observedAt/1000,resetKnown=Number.isFinite(reset)&&reset>0;
  const restored=!!old&&Number.isFinite(old.resetsAt)&&old.resetsAt>0&&old.resetsAt<=seconds&&resetKnown&&reset>seconds&&reset>old.resetsAt&&remaining>=old.remaining+1;
  const row={remaining,resetsAt:resetKnown?reset:null,lowSent:old?.lowSent??false,nearSent:old?.nearSent??false};
  const label=window.minutes===300?'5小时额度':window.minutes===10080?'每周额度':'订阅额度';
  const notify=(kind,text)=>{if(enabled)events.push({id:snapshot.observedAt+':'+key+':'+kind,kind,text,at:snapshot.observedAt})};
  if(restored){notify('restored',label+'已确认恢复，当前剩余 '+remaining.toFixed(0)+'%');row.lowSent=false;row.nearSent=false}
  if(remaining>threshold+5)row.lowSent=false;
  if(remaining<=threshold&&!row.lowSent){notify('low',label+'剩余 '+remaining.toFixed(0)+'%，低于提醒线 '+threshold+'%');row.lowSent=true}
  const soon=resetKnown&&reset>seconds&&reset-seconds<=900;
  if(!soon)row.nearSent=false;
  if(soon&&!row.nearSent){notify('reset-soon',label+'预计 '+Math.ceil((reset-seconds)/60)+' 分钟后重置，实际恢复以账户更新为准');row.nearSent=true}
  next[key]=row;
 }
 state.windows=next;state.observedAt=snapshot.observedAt;
 return {state,events};
}
