import {validDebugPort} from './debug-port.mjs';
export async function discover(port=9335){
  if(!validDebugPort(port))throw Error('Invalid local debugging port');
  const origin='http://127.0.0.1:'+port;
  try{
    const response=await fetch(origin+'/json/list',{signal:AbortSignal.timeout(1500)});
    if(!response.ok)throw Error('连接不可用');
    const pages=await response.json();
    const targets=pages.filter(p=>{try{const u=new URL(p.url);return p.type==='page'&&u.protocol==='app:'&&u.hostname==='-'&&u.pathname==='/index.html'&&!/avatar-overlay/.test(u.search);}catch{return false;}});
    if(targets.length!==1)return {connected:false,reason:targets.length?'检测到多个主界面，请只保留一个换肤模式窗口。':'未找到兼容的桌面主界面。'};
    const target=targets[0],ws=new URL(target.webSocketDebuggerUrl);
    if(ws.protocol!=='ws:'||!['127.0.0.1','localhost','[::1]'].includes(ws.hostname)||ws.port!==String(port))throw Error('连接地址不是预期的本机接口');
    return {connected:true,target};
  }catch{return {connected:false,reason:'桌面换肤连接尚未启用。可先使用右侧预览。'};}
}

export async function command(target,method,params={}){
  return new Promise((resolve,reject)=>{
    const socket=new WebSocket(target.webSocketDebuggerUrl);let done=false;
    const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);socket.close();error?reject(error):resolve(value);};
    const timer=setTimeout(()=>finish(Error('桌面连接超时')),7000);
    socket.addEventListener('open',()=>socket.send(JSON.stringify({id:1,method,params})));
    socket.addEventListener('message',event=>{let value;try{value=JSON.parse(event.data);}catch{return;}if(value.id!==1)return;if(value.error)return finish(Error(value.error.message));finish(null,value.result);});
    socket.addEventListener('error',()=>finish(Error('无法连接桌面界面')));
    socket.addEventListener('close',()=>{if(!done)finish(Error('桌面连接已关闭'));});
  });
}
export async function evaluate(target,expression){const value=await command(target,'Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(value.exceptionDetails)throw Error(value.exceptionDetails.exception?.description||'桌面执行失败');return value.result?.value;}
