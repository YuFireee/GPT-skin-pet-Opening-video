import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash,randomBytes} from 'node:crypto';
import {execFile,spawn} from 'node:child_process';
import {promisify} from 'node:util';
import {discover,evaluate,command} from './lib/cdp.mjs';
import {applySkin,restoreSkin,skinStatus,setSkinActivity} from './lib/renderer.mjs';
import {petTheme} from './lib/pet-themes.mjs';
import {resolveCodexExecutable} from './quota-pet/runtime/usage.mjs';
import {createWorkspaceController} from './lib/workspace.mjs';
import {bootShellStatus} from './lib/boot-readiness.mjs';
import {watchBootReadiness,writeBootSignals} from './lib/boot-monitor.mjs';
import {singleFlight} from './lib/single-flight.mjs';
import {themeStartupPending} from './lib/theme-startup.mjs';
import {validDebugPort,freeDebugPort} from './lib/debug-port.mjs';
const run=promisify(execFile),root=path.dirname(fileURLToPath(import.meta.url));
const installationId=createHash('sha256').update(root.toLowerCase()).digest('hex');
const token=randomBytes(32).toString('hex'),profile=path.join(root,'state','desktop-profile');
const defaults={themeId:'sakura-calm-soft-portrait',petId:'sakura-calm-soft-portrait',bootSound:true,sidebar:50,header:32,rail:35,menubar:12,message:46,composer:42,boot:false,companion:false,motion:true};
const themes=[{id:'sakura-calm-soft-portrait',name:'柔光肖像',focusX:.27}];
let settings={...defaults},companion=null,companionIssue=null,operation=false,managedWindowHint=0;
const visuals=new Set();
await fs.mkdir(path.join(root,'state'),{recursive:true});
let debugPort=9335;try{const saved=JSON.parse(await fs.readFile(path.join(root,'state','debug-port.json'),'utf8'));if(validDebugPort(saved.port))debugPort=saved.port;}catch{}
function validate(input){
  if(!input||typeof input!=='object'||Array.isArray(input))throw Error('设置格式不正确');
  if(Object.keys(input).some(k=>!Object.hasOwn(defaults,k)))throw Error('未知设置项');
  const value={...settings,...input};
  petTheme(value.petId);if(typeof value.bootSound!=='boolean')throw Error('声音开关格式不正确');
  if(!themes.some(t=>t.id===value.themeId))throw Error('未找到主题');
  for(const k of ['sidebar','header','rail','menubar','message','composer'])if(!Number.isInteger(value[k])||value[k]<0||value[k]>85)throw Error('透明度应在 0–85 之间');
  if(typeof value.boot!=='boolean'||typeof value.companion!=='boolean'||typeof value.motion!=='boolean')throw Error('开关格式不正确');
  return value;
}
try{const saved=JSON.parse(await fs.readFile(path.join(root,'state','settings.json'),'utf8'));settings=validate({...saved,themeId:'sakura-calm-soft-portrait',petId:defaults.petId,bootSound:saved.bootSound??true});}catch{}
let themeStartupUntil=0;
let autoTheme=false,autoMessage='尚未启用自动换肤',lastThemeCheck=null,monitorBusy=false,pendingShow=false;
try{autoTheme=JSON.parse(await fs.readFile(path.join(root,'state','auto-theme.json'),'utf8')).enabled===true;}catch{}
async function setAutoTheme(enabled){themeStartupUntil=enabled?Date.now()+25000:0;autoTheme=enabled;await fs.writeFile(path.join(root,'state','auto-theme.json'),JSON.stringify({enabled}));autoTheme=enabled;autoMessage=enabled?'自动保持主题已开启；只作用于专用换肤窗口。':'自动保持主题已关闭。';}
async function bridge(action,aspect=16/9){
  const invoke=async()=>{const r=await run('powershell.exe',['-NoProfile','-NonInteractive','-File',path.join(root,'native-bridge.ps1'),'-Action',action,'-Profile',profile,'-AspectRatio',String(aspect),'-WindowHandle',String(managedWindowHint),'-DebugPort',String(debugPort)],{windowsHide:true,timeout:12000,maxBuffer:1024*128});return JSON.parse(r.stdout.replace(/^\uFEFF/,'').trim());};
  try{
    let result=await invoke();
    if((action==='Launch'||action==='LaunchBackground')&&result.portOrphaned===true){
      debugPort=await freeDebugPort();
      await fs.writeFile(path.join(root,'state','debug-port.json'),JSON.stringify({port:debugPort}));
      result=await invoke(); // Exactly one recovery attempt; never kill the old port owner.
    }
    return result;
  }finally{if(action!=='Inspect')connection.invalidate();}
}
async function stopManaged(snapshot){
  const r=await run('powershell.exe',['-NoProfile','-NonInteractive','-File',path.join(root,'native-bridge.ps1'),'-Action','StopManaged','-Profile',profile,'-ExpectedPid',String(snapshot.managedRootPid),'-ExpectedCreated',snapshot.managedRootCreated,'-DebugPort',String(debugPort)],{windowsHide:true,timeout:12000,maxBuffer:1024*128});
  return JSON.parse(r.stdout.replace(/^\uFEFF/,'').trim());
}
const connection=singleFlight(async()=>{const local=await bridge('Inspect');if(!local.owned)return {...local,connected:false,reason:local.reason||'尚未开启本工具专用的换肤连接。'};if(!local.window)return {...local,connected:false,reason:'换肤后台仍在运行，但专用桌面窗口已关闭。点击启动并自动换肤可重新打开。'};const found=await discover(debugPort);return {...local,...found};});
const publicConnection=({target,...rest})=>rest;
async function startVisual(mode,themeId=settings.themeId,liveHandoff=false,initialTarget=null,waitReady=false,backgroundMain=false){
  const theme=mode==='Companion'?{id:themeId}:themes.find(t=>t.id===themeId);
  const readyFile=path.join(root,'state','visual-'+randomBytes(12).toString('hex')+'.json');
  if(initialTarget)await fs.writeFile(readyFile+'.target',String(initialTarget.handle)+' '+String(initialTarget.pid));
  let child;
  if(mode==='Companion'){
    const codexPath=resolveCodexExecutable();
    if(!codexPath)throw Error('未找到额度查询程序，已停止；请检查安装后手动重试。');
    const dataDir=path.join(root,'state','quota-pet');await fs.mkdir(dataDir,{recursive:true});
    const configPath=path.join(dataDir,'installation.json');
    await fs.writeFile(configPath,JSON.stringify({version:'1.3.4-sakura',readinessMode:'native-window',themeId:theme.id,spriteFile:petTheme(theme.id).sprite,appDir:path.join(root,'quota-pet'),dataDir,nodePath:process.execPath,codexPath}));
    child=spawn('powershell.exe',['-NoLogo','-NoProfile','-STA','-File',path.join(root,'quota-pet','widget.ps1'),'-ConfigurationPath',configPath,'-ReadyFile',readyFile,'-ParentProcessId',String(process.pid)],{windowsHide:true,stdio:'ignore'});
  }else child=spawn(path.join(root,mode==='Boot'?'SakuraBoot.exe':'SakuraVisual.exe'),[mode,path.join(root,'assets',theme.id+'.png'),readyFile,...(mode==='Boot'?['--video',path.join(root,'assets','sakura-opening.mp4')]:[]),...(liveHandoff?['--handoff']:[]),...(settings.bootSound?['--sound']:[]),...(waitReady?['--wait-ready']:[]),...(backgroundMain?['--background-main']:[])],{windowsHide:false,stdio:'ignore'});
  child.sakuraMode=mode;child.sakuraReadyFile=readyFile;child.sakuraThemeId=theme.id;visuals.add(child);child.once('exit',()=>visuals.delete(child));
  let launchError=null;child.on('error',error=>{launchError=error;visuals.delete(child);});
  const ready=(async()=>{const end=Date.now()+20000;while(Date.now()<end){
    if(launchError)throw Error('角色窗口未能启动：'+launchError.message);
    try{const state=JSON.parse(await fs.readFile(readyFile,'utf8'));
      if(state.state==='error')throw Error(state.error||'角色窗口启动失败');
      if(state.pid===child.pid&&((state.shown&&(state.state==='ready'||state.state==='closed'))||(mode==='Companion'&&state.state==='waiting'&&!state.shown)))return state;
    }catch(error){if(error.code!=='ENOENT'&&!(error instanceof SyntaxError)){child.kill();throw error;}}
    if(child.exitCode!==null)throw Error('窗口未显示就已退出，请检查本机窗口组件。');
    await new Promise(resolve=>setTimeout(resolve,80));
  }child.kill();throw Error('未收到窗口已显示的确认，已停止启动。');})();
  return {child,ready,readyFile};
}
async function stopVisual(child){
  if(!child||child.exitCode!==null)return;
  if(child.sakuraReadyFile)await fs.writeFile(child.sakuraReadyFile+'.stop','stop');
  await new Promise(resolve=>{const timer=setTimeout(resolve,1600);child.once('exit',()=>{clearTimeout(timer);resolve();});});
  if(child.exitCode===null)child.kill();
}
async function applySelected(config,c){
  const selectors=JSON.parse(await fs.readFile(path.join(root,'lib','selectors.json'),'utf8'));
  const theme=themes.find(t=>t.id===config.themeId);
  const image='data:image/png;base64,'+(await fs.readFile(path.join(root,'assets',theme.id+'.png'))).toString('base64');
  const parts={main:selectors['shell-main'],backdrop:selectors['native-backdrops'],sidebar:selectors['left-panel'],header:selectors['header-tint'],menubar:selectors['menu-bar'],rail:selectors['icon-rail'],home:selectors['home-route'],thread:selectors['thread-surface'],composer:selectors['composer-chrome'],toolbar:selectors['composer-toolbar'],message:selectors.message,dialog:selectors['overlay-dialog']+', '+selectors['overlay-menu']};
  const result=await evaluate(c.target,`(${applySkin.toString()})(${JSON.stringify({...config,image,selectors,parts,focusX:theme.focusX,active:c.window?.visible===true&&!c.window.minimized&&c.window.foreground===true})})`);
  const verified=await evaluate(c.target,`(${skinStatus.toString()})()`);
  if(!verified.active||verified.themeId!==theme.id)throw Error('背景解码或样式核验未通过，不能确认换肤成功。');
  if(companion)await ensureCompanion(true,config);result.verification=verified;return result;
}
async function showManaged(){try{
  const local=await bridge('Inspect');if(!local.owned)throw Error(local.reason);
  if(local.window?.minimized)await bridge('Reveal');
  const found=await discover(debugPort);if(!found.connected)throw Error(found.reason);
  // Ask the application renderer to activate through its own lifecycle.
  // Never resurrect a hidden host HWND with Win32 ShowWindow.
  await command(found.target,'Page.bringToFront');
  await new Promise(resolve=>setTimeout(resolve,350));
  const state=await evaluate(found.target,`(${skinStatus.toString()})()`);
  return {shown:state.pageVisible,pageVisible:state.pageVisible,foreground:state.pageVisible&&state.focused,error:state.pageVisible?null:'应用主界面仍处于后台隐藏状态。请使用“修复无响应窗口”重新打开专用窗口。'};
}catch(error){return {shown:false,pageVisible:false,foreground:false,error:error.message};}}
async function keepTheme(){
  if(!autoTheme||operation||monitorBusy||workspace.active())return;monitorBusy=true;let claimed=false;
  try{
    const c=await connection();
    if(!autoTheme||operation||workspace.active())return;
    operation=true;claimed=true;
    if(!c.connected){if(themeStartupPending(c,themeStartupUntil)){autoMessage='专用应用正在创建窗口，等待主界面就绪…';return;}await setAutoTheme(false);autoMessage='自动检查已停止：'+c.reason+' 请手动连接后再应用主题。';return;}
    if(themeStartupPending(c,themeStartupUntil)){
      const selectors=JSON.parse(await fs.readFile(path.join(root,'lib','selectors.json'),'utf8'));
      const shell=await evaluate(c.target,`(${bootShellStatus.toString()})(${JSON.stringify(selectors)})`);
      if(!shell?.ready){autoMessage='专用窗口正在加载主界面…';return;}
    }
    const status=await evaluate(c.target,`(${skinStatus.toString()})()`);
    if(!status.active||status.rendererVersion!==4){await applySelected(settings,c);autoMessage='已自动恢复专用窗口的主题。';}
    else autoMessage=status.pageVisible?'专用窗口主题已加载。':'主题已加载到隐藏的专用窗口；点击“显示已换肤窗口”查看。';
    await evaluate(c.target,`(${setSkinActivity.toString()})(${c.window?.visible===true&&!c.window.minimized&&c.window.foreground===true})`);
    if(pendingShow){const shown=await showManaged();if(shown.shown)pendingShow=false;}
    lastThemeCheck=new Date().toISOString();
  }catch(error){await setAutoTheme(false).catch(()=>{});autoMessage='自动检查已停止：'+error.message+'；请手动重试。';}
  finally{if(claimed)operation=false;monitorBusy=false;}
}
let repairing=false;
const themeTimer=setInterval(()=>{if(!repairing)void keepTheme();},2500);themeTimer.unref();
async function ensureCompanion(enabled,config=settings){
  companionIssue=null;
  if(companion&&(!enabled||companion.sakuraThemeId!==config.petId)){await stopVisual(companion);companion=null;}
  if(enabled&&!companion){const visual=await startVisual('Companion',config.petId);await visual.ready;if(visual.child.exitCode!==null)throw Error('角色小窗在就绪后退出，请重试。');companion=visual.child;visual.child.once('exit',()=>{if(companion===visual.child){companion=null;void fs.readFile(visual.readyFile,'utf8').then(raw=>{const ended=JSON.parse(raw);if(!companion&&ended.error)companionIssue=ended.error;}).catch(()=>{});}});}
  return {running:!!companion};
}
async function startBoot(config,preview=false){
  for(const child of [...visuals].filter(v=>v.sakuraMode==='Boot'&&v.exitCode===null)){
    if(preview)throw Error('已有启动动画正在播放，请结束后再预览。');
    await stopVisual(child);
  }
  const blue=true;
  let initialTarget=null;
    // Spawn the opening before any process inspection or application launch.
  const visual=await startVisual('Boot',config.themeId,blue,initialTarget,false,!preview);
  let active=true,timedOut=false;
  const deadline=setTimeout(()=>{if(active){timedOut=true;void stopVisual(visual.child).catch(()=>{});}},45000);
  deadline.unref();
  visual.child.once('exit',()=>{active=false;clearTimeout(deadline);});
  visual.child.once('error',()=>{active=false;clearTimeout(deadline);});
  const prepare=(async()=>{
    if(!blue)return;
    const selectors=JSON.parse(await fs.readFile(path.join(root,'lib','selectors.json'),'utf8'));
    await watchBootReadiness({
      active:()=>active,inspect:connection,
      shell:async c=>{
        const result=await evaluate(c.target,`(${bootShellStatus.toString()})(${JSON.stringify(selectors)})`);
        if(preview&&c.window.minimized&&result.ready){await bridge('Reveal');return {ready:false};}
        return result;
      },
      publish:(target,ready)=>writeBootSignals(visual.readyFile,target,ready),
    });
  })();
  visual.finished=(async()=>{
    await visual.ready;
    if(visual.child.exitCode===null)await new Promise((resolve,reject)=>{
      visual.child.once('exit',()=>{resolve();});
    });
    active=false;
    await prepare;
    const ended=JSON.parse(await fs.readFile(visual.readyFile,'utf8'));
    await Promise.all(['.target','.target.tmp','.desktop-ready','.stop'].map(suffix=>fs.rm(visual.readyFile+suffix,{force:true})));
    if(timedOut)throw Error('主窗口在45秒内未就绪，已停止开场和自动等待。请检查应用后手动重试。');
    if(ended.state!=='closed')throw Error('开场结束未确认。');
    if(!preview&&ended.reason==='completed'&&!['live-window','visible-window-fade'].includes(ended.handoff))throw Error('视频已播放，但主界面尚未就绪，未完成窗口衔接。');
    if(ended.mediaState==='failed')throw Error('视频播放失败，已使用静态主题图进入。');
    return ended;
  })();
  visual.finished.catch(()=>{});prepare.catch(()=>{});
  return visual;
}
const workspace=createWorkspaceController({connection,launch:config=>bridge(config.boot?'LaunchBackground':'Launch'),apply:async(config,c)=>{const result=await applySelected(config,c);await setAutoTheme(true);result.window=await showManaged();return result;},beginBoot:async config=>{const visual=await startBoot(config);await visual.ready;return {finished:visual.finished,stop:()=>stopVisual(visual.child)};},ensureCompanion});
async function companionDisplay(){if(!companion)return {visible:false,waiting:false};try{const state=JSON.parse(await fs.readFile(companion.sakuraReadyFile,'utf8'));return {visible:state.state==='ready'&&state.shown===true,waiting:state.state==='waiting'};}catch{return {visible:false,waiting:true};}}
async function quotaStatus(){
  try{const value=JSON.parse(await fs.readFile(path.join(root,'state','quota-pet','status.json'),'utf8'));return {ok:value.ok===true,stale:Date.now()-Number(value.checkedAt??0)>180000,checkedAt:value.checkedAt??null,error:typeof value.error==='string'?value.error:null,windows:Array.isArray(value.windows)?value.windows.map(w=>({label:w.label,remaining:w.remaining,resetsAt:w.resetsAt})):[]};}catch{return {ok:false,windows:[],error:'尚未读取额度；打开桌宠后会自动查询。'};}
}
async function body(req){let raw='';for await(const chunk of req){raw+=chunk;if(raw.length>8192)throw Error('请求过大');}return raw?JSON.parse(raw):{};}
function json(res,status,value){res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}).end(JSON.stringify(value));}
const files=new Map([['/','index.html'],['/app.js','app.js'],['/lib/pet-themes.mjs','lib/pet-themes.mjs'],['/style.css','style.css'],['/theme-preview.html','theme-preview.html'],['/preview-data.js','preview-data.js'],['/preview-motion.js','preview-motion.js'],['/acceptance.html','acceptance.html']]);
files.set('/assets/sakura-pet.png','quota-pet/assets/sakura-soft-bust.png');
files.set('/assets/sakura-soft-pet.png','quota-pet/assets/sakura-soft-bust.png');
for(const t of themes)files.set('/assets/'+t.id+'.png','assets/'+t.id+'.png');
const mime={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.mjs':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png'};
const server=http.createServer(async(req,res)=>{
  res.setHeader('X-Content-Type-Options','nosniff');res.setHeader('X-Frame-Options','SAMEORIGIN');res.setHeader('Content-Security-Policy',"frame-ancestors 'self'; base-uri 'none'; object-src 'none'");res.setHeader('Referrer-Policy','no-referrer');res.setHeader('Cross-Origin-Resource-Policy','same-origin');
  const host='127.0.0.1:'+server.address().port;
  if(req.headers.host!==host)return json(res,403,{error:'仅接受本机访问'});
  const url=new URL(req.url,'http://'+host);
  if(url.pathname==='/health'&&req.method==='GET')return json(res,200,{service:'sakura-studio',version:'0.9.6',installationId,pid:process.pid,debugPort});
  if(url.pathname.startsWith('/api/')){
    if(req.headers['x-sakura-token']!==token)return json(res,403,{error:'请求验证失败，请刷新控制中心。'});
    if(req.headers.origin&&req.headers.origin!=='http://'+host)return json(res,403,{error:'不接受跨站请求'});
    try{
      if(url.pathname==='/api/workspace'&&req.method==='GET')return json(res,200,{job:workspace.snapshot()});
      if(url.pathname==='/api/control-state'&&req.method==='GET')return json(res,200,{settings,companionRunning:!!companion,companionIssue,companionDisplay:await companionDisplay(),autoTheme:{enabled:autoTheme,message:autoMessage},workspace:workspace.snapshot()});
      if(url.pathname==='/api/status'&&req.method==='GET'){
        const c=await connection();let desktop={active:false};if(c.connected)desktop=await evaluate(c.target,`(${skinStatus.toString()})()`);
        return json(res,200,{settings,themes,connection:publicConnection(c),desktop,autoTheme:{enabled:autoTheme,message:autoMessage,lastCheck:lastThemeCheck},companionRunning:!!companion,companionIssue,companionDisplay:await companionDisplay(),quota:await quotaStatus(),workspace:workspace.snapshot(),version:'0.9.6'});
      }
      if(req.method!=='POST')return json(res,405,{error:'不支持此请求'});
      const input=await body(req);
      if(workspace.active()&&!['/api/workspace/cancel','/api/quit'].includes(url.pathname))return json(res,409,{error:'一键流程正在进行，请先取消并等待结束。'});
      if(operation)return json(res,409,{error:'上一项操作尚未完成'});operation=true;
      try{
        if(url.pathname==='/api/workspace/start')return json(res,202,{job:workspace.start(settings)});
        if(url.pathname==='/api/workspace/cancel'){workspace.cancel(input.id);await Promise.all([...visuals].filter(v=>v.sakuraMode==='Boot').map(stopVisual));return json(res,202,{job:workspace.snapshot()});}
        if(url.pathname==='/api/settings'){
          settings=validate(input);await fs.writeFile(path.join(root,'state','settings.json'),JSON.stringify(settings,null,2));return json(res,200,{settings,message:'设置已保存；桌面效果需点击“应用到桌面”。'});
        }
        if(url.pathname==='/api/apply'||url.pathname==='/api/restore'){
          if(url.pathname==='/api/restore')await setAutoTheme(false);
          const c=await connection();
          if(!c.connected){
            if(url.pathname==='/api/restore')return json(res,409,{error:'自动保持已关闭；窗口未连接，无法确认已移除样式。'+c.reason});
            const launch=await bridge('Launch');if(!launch.started)return json(res,409,{error:launch.reason});
            await setAutoTheme(true);pendingShow=true;return json(res,202,{pending:true,message:'已准备专用窗口，正在等待主界面并自动应用主题；首次使用请先登录。当前普通窗口不会改变。'});
          }
          let result;
          if(url.pathname==='/api/restore')result=await evaluate(c.target,`(${restoreSkin.toString()})()`);
          else{
            result=await applySelected(settings,c);await setAutoTheme(true);
            result.window=await showManaged();
          }
          return json(res,200,{result,message:result.applied?(result.window.pageVisible&&result.window.foreground?'专用换肤窗口已显示在前台，背景图片与样式已加载；普通窗口保持原样。':'主题已加载到专用换肤窗口；系统未确认前台切换，请从任务栏选择该窗口。普通窗口保持原样。'):'已移除本工具样式并关闭自动保持主题。'});
        }
        if(url.pathname==='/api/repair'){
          if(input.confirmRestart!==true)throw Error('请先确认重开专用窗口，并保存该窗口内的内容。');
          repairing=true;
          try{
          const local=await bridge('Inspect');if(!local.owned)throw Error('无法验证专用进程身份，未关闭任何窗口。');
          const found=await discover(debugPort);if(!found.connected)throw Error(found.reason);
          try{await command(found.target,'Browser.close');}catch(error){if(!/连接已关闭|无法连接桌面界面|连接超时/.test(error.message))throw error;}
          let stopped=false;
          for(let attempt=0;attempt<2;attempt++){
            const remaining=await bridge('Inspect');
            if(remaining.managedProcessCount===0&&remaining.listenerCount===0){stopped=true;break;}
            await new Promise(resolve=>setTimeout(resolve,350));
          }
          if(!stopped){const closed=await stopManaged(local);if(!closed.stopped)throw Error('专用实例尚未结束，未启动新的窗口。');}
          managedWindowHint=0;
          const launch=await bridge('Launch');if(!launch.started)throw Error(launch.reason);
          await setAutoTheme(true);pendingShow=false;
          return json(res,202,{pending:true,message:'专用应用已按正常流程重新启动；等待主界面后自动加载主题。普通窗口和登录资料保持原样。'});
          }finally{repairing=false;}
        }
        if(url.pathname==='/api/show'){const result=await showManaged();if(!result.shown)throw Error(result.error||'未能显示专用窗口');return json(res,200,{result,message:result.foreground?'专用换肤窗口已切到前台。':'已请求显示专用窗口；系统未确认切到前台，请从任务栏选择。'});}
        if(url.pathname==='/api/launch'){
          const result=await bridge('Launch');if(!result.started)return json(res,409,{error:result.reason});
          await setAutoTheme(true);
          pendingShow=!result.reused;
          if(result.reused){const c=await connection();if(c.connected)await applySelected(settings,c);result.window=await showManaged();}
          return json(res,200,{result,message:'已准备专用换肤窗口并开启自动应用。首次请登录；进入主界面后自动加载保存的主题。普通启动入口不受影响。'});
        }
        if(url.pathname==='/api/boot-preview'){const previewTheme=input.themeId??settings.themeId;if(!themes.some(t=>t.id===previewTheme))throw Error('未知开场主题');const visual=await startBoot({...settings,themeId:previewTheme},true);await visual.ready;return json(res,200,{message:'开场已打开；主窗口就绪后右上角会显示 Esc 跳过。'});}
        if(url.pathname==='/api/pet-theme'){
          const next=validate({...settings,petId:input.petId});const previous=settings,wasRunning=!!companion;
          try{await ensureCompanion(wasRunning,next);await fs.writeFile(path.join(root,'state','settings.json'),JSON.stringify(next,null,2));settings=next;}
          catch(error){try{await ensureCompanion(wasRunning,previous);}catch{}throw error;}
          return json(res,200,{petId:settings.petId,running:!!companion,message:'已切换为'+petTheme(settings.petId).name+'，界面主题保持柔光肖像。'});
        }
        if(url.pathname==='/api/companion'){
          if(typeof input.enabled!=='boolean')throw Error('挂件开关格式不正确');
          await ensureCompanion(input.enabled);
          return json(res,200,{running:!!companion,message:companion?((await companionDisplay()).waiting?'桌宠已启动，当前跟随的主窗口不可见或尚未就绪，正在等待；显示主窗口后会自动出现。':'樱色额度桌宠已显示：点角色看真实剩余额度，拖动可调整位置，右键打开设置。'):'角色小窗已关闭。'});
        }
        if(url.pathname==='/api/quit'){
          if(workspace.active())workspace.cancel(workspace.snapshot().id);
          try{const c=await connection();if(c.connected)await evaluate(c.target,`(${restoreSkin.toString()})()`);}catch{}
          await stopVisual(companion);companion=null;
          json(res,200,{message:'工具已关闭。桌面应用继续运行；退出换肤连接请完整退出专用桌面窗口。'});
          setTimeout(shutdown,250);return;
        }
        return json(res,404,{error:'未找到操作'});
      }finally{operation=false;}
    }catch(error){return json(res,400,{error:error.message});}
  }
  if(req.method!=='GET'&&req.method!=='HEAD')return json(res,405,{error:'不支持此请求'});
  const file=files.get(url.pathname);if(!file)return json(res,404,{error:'未找到文件'});
  try{let data=await fs.readFile(path.join(root,file));if(file==='index.html')data=Buffer.from(data.toString().replace('__SESSION_TOKEN__',token));res.setHeader('Content-Type',mime[path.extname(file)]);res.setHeader('Cache-Control','no-store');res.end(req.method==='HEAD'?undefined:data);}catch{json(res,404,{error:'文件不可用'});}
});
const port=Number(process.env.SAKURA_PORT||56895);
server.listen(port,'127.0.0.1',async()=>{const url=`http://127.0.0.1:${server.address().port}/`;await fs.writeFile(path.join(root,'state','session.json'),JSON.stringify({pid:process.pid,url}));console.log('SAKURA_STUDIO_URL='+url);
  // Native tray host: no hidden browser, no restart loop; isolated test ports never start it.
  if(server.address().port===56895&&process.env.SAKURA_CONTROL_OFF!=='1'){
    const executable=path.join(root,'SakuraControl.exe');
    try{await fs.access(executable);const host=spawn(executable,['--parent',String(process.pid),'--port',String(server.address().port)],{windowsHide:true,stdio:'ignore'});host.on('error',error=>console.error('Native control host: '+error.message));host.unref();}catch{}
  }
});
async function shutdown(){clearInterval(themeTimer);await Promise.allSettled([...visuals].map(stopVisual));server.close();process.exit();}
process.on('SIGINT',shutdown);process.on('SIGTERM',shutdown);
