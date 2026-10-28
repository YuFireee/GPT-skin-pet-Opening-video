// Three animation states only. No titles, message text, tool arguments or history.
const ttl=10*60*1000;
const nameOf=value=>typeof value==='string'?value.split(/[./]/).at(-1).toLowerCase():'';
export function reduceDialogState(previous,record,now=Date.now()){
 const p=record?.payload??{},at=Date.parse(record?.timestamp);
 if(!Number.isFinite(at)||at<now-ttl||at>now+60000||at<(previous?.at??0))return previous;
 const type=nameOf(p.type),kind=nameOf(record.type);
 let state,reason,pending=previous?.pending??null;
 const running=why=>{state='running';reason=why;pending=null};
 const waiting=(why,id)=>{state='confirmation';reason=why;pending=typeof id==='string'?id.slice(0,120):null};
 const normal=why=>{state='normal';reason=why;pending=null};
 if(kind==='event_msg'){
  if(['task_complete','task_completed','turn_complete','turn_completed','turn_aborted','task_aborted','task_failed','turn_failed'].includes(type))normal('terminal');
  else if(['task_started','turn_started','task_start','agent_thinking','exec_command_begin'].includes(type))running('started');
  else if(['approval_request','approval_requested','request_approval','request_user_input','input_required'].includes(type))waiting('explicit_request',p.call_id??p.request_id);
  else if(['approval_response','approval_resolved','user_input_received'].includes(type))running('confirmed');
  else if(['item_started','item_completed'].includes(type)){
   const item=p.item??{},itemType=nameOf(item.type);
   if(itemType==='agentmessage'&&item.phase==='final')normal('final_message');
   else if(['reasoning','commandexecution','toolcall'].includes(itemType)&&previous?.state!=='confirmation')running('active_item');
  }
 }else if(kind==='response_item'){
  if(type==='message'&&p.role==='user')running('user_turn');
  else if(type==='message'&&p.role==='assistant'&&p.phase==='final')normal('final_message');
  else if(type==='message'&&p.role==='assistant'&&p.phase==='commentary'&&previous?.state!=='confirmation')running('commentary');
  else if(type==='reasoning'&&previous?.state!=='confirmation')running('reasoning');
  else if(['function_call','custom_tool_call'].includes(type)){
   const tool=nameOf(p.name);
   if(['request_user_input','request_permissions'].includes(tool))waiting('blocking_tool',p.call_id);
   else if(tool==='request_user_input_async'){if(previous?.state!=='confirmation')running('nonblocking_question');}
   else if(previous?.state!=='confirmation')running('tool_call');
  }else if(['function_call_output','custom_tool_call_output'].includes(type)){
   if(previous?.state!=='confirmation'||(pending&&p.call_id===pending))running('tool_return');
  }
 }
 if(!state)return previous;
 return {state,at,reason,pending};
}
export function summarizeDialogState(entries,now=Date.now()){
 let latest=null;
 for(const entry of entries){const value=entry.dialog;if(!entry.archived&&value&&value.at>=now-ttl&&value.at<=now+60000&&(!latest||value.at>latest.at))latest=value;}
 return latest?{state:latest.state,observedAt:latest.at,reason:latest.reason,source:'local-log'}:{state:'normal',observedAt:null,reason:'no_recent_signal',source:'local-log'};
}
