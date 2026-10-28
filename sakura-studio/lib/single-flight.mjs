// Share an in-progress inspection and briefly reuse its result. No retries.
export function singleFlight(load,{ttlMs=750,now=Date.now}={}){
  let pending=null,value,expires=0,generation=0;
  const probe=()=>{
    if(pending)return pending;
    if(now()<expires)return Promise.resolve(value);
    const epoch=generation;
    const request=Promise.resolve().then(load).then(result=>{if(epoch===generation){value=result;expires=now()+ttlMs}return result});
    pending=request;request.finally(()=>{if(pending===request)pending=null}).catch(()=>{});return request;
  };
  probe.invalidate=()=>{generation++;expires=0;pending=null};return probe;
}
