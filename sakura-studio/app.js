import {petTheme} from './lib/pet-themes.mjs';

const clientVersion='0.9.6';

let stale=false,lastCompanionIssue="";

const $=s=>document.querySelector(s),token=$('meta[name=sakura-token]').content;

let settings={themeId:'sakura-calm-soft-portrait',petId:'sakura-calm-soft-portrait',bootSound:true,sidebar:50,header:32,rail:35,menubar:12,message:46,composer:42,boot:false,companion:false,motion:true};

const message=(text,tone='info')=>{$('#notice').textContent=text;$('#notice').dataset.tone=tone;};

function offline(reason){$('#connection').textContent='本地后台未连接';$('#dot').classList.remove('ready');$('#connection-detail').textContent='请双击启动樱色工坊，恢复后台后刷新本页。';$('#applied').textContent='更换状态：无法核验';message(reason,'error');}

function requireReload(version){stale=true;$('#update-banner').hidden=false;if(version)$('#runtime-version').textContent='后台 '+version+' · 本页需要刷新';lockWorkspaceControls();}

$('#reload-page').onclick=()=>location.reload();

async function api(route,data){if(stale)throw Error('工具已更新，请使用上方按钮刷新本页后继续。');let response;try{response=await fetch('/api/'+route,{method:data===undefined?'GET':'POST',headers:{'X-Sakura-Token':token,'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data),signal:AbortSignal.timeout(route==='repair'?65000:25000)});}catch{const error=Error('无法联系本地后台，操作未执行。请重新启动樱色工坊后刷新页面。');error.offline=true;throw error;}let result;try{result=await response.json();}catch{throw Error('后台返回异常，请重新启动工具并刷新页面。');}if(response.status===403){requireReload();throw Error('本页连接凭据已过期，请刷新本页后继续。');}if(!response.ok)throw Error(result.error||'操作未完成');return result;}

function preview(){const frame=$('#preview').contentWindow;frame?.setStudioTheme?.(settings);}

function sync(){const pet=petTheme(settings.petId);$('#pet-preview').src=pet.preview;$('#pet-preview').alt=pet.name;$('#pet-theme-label').textContent='当前桌宠：'+pet.name;for(const key of ['sidebar','header','rail','menubar','message','composer']){$('#'+key).value=settings[key];$('#'+key+'-value').textContent=settings[key]+'%';}document.querySelectorAll('[data-theme]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.theme===settings.themeId)));document.querySelectorAll('[data-pet]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.pet===settings.petId)));$('#boot-sound').checked=settings.bootSound;$('#background-motion').checked=settings.motion!==false;$('#boot-enabled').checked=settings.boot;$('#companion-enabled').checked=settings.companion;preview();}

let busy=false,workspaceJob=null,companionRunning=false,pollingWorkspace=false,nextWorkspacePoll=0;

async function action(button,fn){if(stale){message('工具已更新，请先刷新本页。','error');return;}if(busy){message('上一项操作仍在进行，请稍候。','busy');return;}busy=true;const label=button.textContent||button.parentElement?.textContent?.trim()||'执行操作',buttons=[...document.querySelectorAll('button')];buttons.forEach(b=>b.disabled=true);button.disabled=true;lockWorkspaceControls();message('正在'+label+'…','busy');try{await fn();}catch(error){if(error.offline)offline(error.message);else message('操作未成功：'+error.message,'error');}finally{buttons.forEach(b=>b.disabled=false);button.disabled=false;$('#reload-page').disabled=false;busy=false;lockWorkspaceControls();}}

async function refresh(loadSettings=false){

  const result=await api('status');
  if(result.companionIssue&&result.companionIssue!==lastCompanionIssue&&!busy){message(result.companionIssue,'error');lastCompanionIssue=result.companionIssue;}else if(!result.companionIssue)lastCompanionIssue='';

  $('#runtime-version').textContent='运行版本 · '+(result.version??clientVersion);

  if(result.version&&result.version!==clientVersion){requireReload(result.version);return;}

  $('#checked-at').textContent='最后检查：'+new Date().toLocaleTimeString('zh-CN',{hour12:false});

  $('#visibility-status').textContent='窗口显示：'+(!result.connection.connected?'尚未连接':result.desktop.pageVisible?(result.desktop.focused?'页面可见 · 已获焦点':'页面可见 · 未获焦点'):'页面可见性未确认；主题加载不代表窗口已显示');

  if(loadSettings){settings=result.settings;sync();}

  $('#connection').textContent=result.connection.connected?'专用窗口已连接（普通窗口未接管）':'预览可用 · 专用窗口未连接';

  $('#dot').classList.toggle('ready',result.connection.connected);

  const win=result.connection.window;

  $('#connection-detail').textContent=result.connection.connected?

    ('受管窗口进程 '+(win?.pid??'未知')+' · '+(win?.minimized?'已最小化':win?.foreground?'位于前台':'未在前台')+'。可点击“显示已换肤窗口”。'):result.connection.reason;

  $('#applied').textContent=result.desktop.active?

    '专用窗口主题已加载：'+(result.themes.find(t=>t.id===result.desktop.themeId)?.name||'自定义主题')+(result.desktop.pageVisible?'':'（当前隐藏）'):

    '专用窗口主题：尚未确认加载';

  $('#auto-status').textContent='自动保持：'+(result.autoTheme?.enabled?'开启 · ':'关闭 · ')+(result.autoTheme?.message??'');

  const quota=result.quota;$('#quota-summary').textContent=quota?.ok?('剩余额度：'+quota.windows.map(w=>w.label+' '+Math.round(w.remaining)+'%').join(' · ')+(quota.stale?'（旧快照，请刷新桌宠）':'')):('额度：'+(quota?.error??'打开桌宠后读取。'));

  companionRunning=result.companionRunning;

  $('#companion-runtime').textContent=companionRunning?(result.companionDisplay?.waiting?'桌宠正在等待可见的主窗口。':'桌宠当前已显示。'):'桌宠当前未运行。';

  $('#companion-toggle').textContent=companionRunning?'现在关闭小窗':'现在显示小窗';

  renderWorkspace(result.workspace);

}

for(const key of ['sidebar','header','rail','menubar','message','composer'])$('#'+key).addEventListener('input',()=>{settings[key]=Number($('#'+key).value);$('#'+key+'-value').textContent=settings[key]+'%';preview();message('预览已更新；点击保存或应用到桌面以保留设置。');});

document.querySelectorAll('[data-theme]').forEach(button=>button.addEventListener('click',()=>{settings.themeId=button.dataset.theme;sync();}));

document.querySelectorAll('[data-tab]').forEach(button=>button.addEventListener('click',()=>{document.querySelectorAll('.tab').forEach(el=>el.hidden=el.id!==button.dataset.tab);document.querySelectorAll('[data-tab]').forEach(b=>b.setAttribute('aria-selected',String(b===button)));}));

document.querySelectorAll('[data-route]').forEach(button=>button.addEventListener('click',()=>{$('#preview').contentWindow.setStudioRoute?.(button.dataset.route);document.querySelectorAll('[data-route]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));}));

$('#preview').addEventListener('load',preview);

$('#save').onclick=()=>action($('#save'),async()=>{message((await api('settings',settings)).message);});

$('#apply').onclick=()=>action($('#apply'),async()=>{await api('settings',settings);const result=await api('apply',{});await refresh();message(result.message,result.pending||result.result?.window?.pageVisible===false?'info':'success');});

$('#restore').onclick=()=>action($('#restore'),async()=>{const result=await api('restore',{});await refresh();message(result.message,'success');});

async function check(){await refresh();message($('#connection').textContent+'；'+$('#applied').textContent,$('#dot').classList.contains('ready')?'success':'info');}

$('#refresh').onclick=()=>action($('#refresh'),check);

$('#connect').onclick=()=>action($('#connect'),check);

$('#show-launch').onclick=()=>$('#launch').click();

$('#repair-window').onclick=()=>action($('#repair-window'),async()=>{if(!confirm('将退出并重开本工具专用窗口，必要时结束其残留后台。请先保存专用窗口中的内容；普通窗口不会被关闭。继续吗？'))return;message((await api('repair',{confirmRestart:true})).message);await refresh();});

$('#show-window').onclick=()=>action($('#show-window'),async()=>{const result=await api('show',{});await refresh();message(result.message,result.result.foreground?'success':'info');});

$('#quit').onclick=()=>action($('#quit'),async()=>{message((await api('quit',{})).message);setTimeout(()=>document.querySelectorAll('button,input').forEach(el=>el.disabled=true),0);});

$('#launch').onclick=()=>action($('#launch'),async()=>{await api('settings',settings);message((await api('launch',{})).message);await refresh();});

async function saveModuleFlag(key,id){const previous=settings[key];settings[key]=$(id).checked;await action($(id),async()=>{try{message((await api('settings',settings)).message);}catch(error){settings[key]=previous;$(id).checked=previous;throw error;}});}

$('#boot-enabled').onchange=()=>saveModuleFlag('boot','#boot-enabled');

$('#companion-enabled').onchange=()=>saveModuleFlag('companion','#companion-enabled');

$('#boot-preview').onclick=()=>action($('#boot-preview'),async()=>message((await api('boot-preview',{themeId:'sakura-calm-soft-portrait'})).message));

$('#companion-toggle').onclick=()=>action($('#companion-toggle'),async()=>{const result=await api('companion',{enabled:!companionRunning});await refresh();message(result.message);});

function lockWorkspaceControls(){const active=workspaceJob?.state==='running';for(const selector of ['#save','#apply','#restore','#launch','#show-launch','#repair-window','#workspace-start','#boot-preview','#companion-toggle','[data-theme]','[data-pet]','input'])document.querySelectorAll(selector).forEach(el=>el.disabled=stale||busy||active);$('#workspace-cancel').hidden=!active;$('#workspace-cancel').disabled=busy||workspaceJob?.cancelRequested;}

function renderWorkspace(job){const previous=workspaceJob;if(previous&&job&&Date.parse(job.startedAt)<Date.parse(previous.startedAt))return;if(previous?.id===job?.id&&previous?.state!=='running'&&job?.state==='running')return;if(previous&&!job)return;const changed=previous?.id!==job?.id||previous?.state!==job?.state||previous?.message!==job?.message;workspaceJob=job??null;const labels={pending:'待开始',running:'进行中',complete:'已完成',skipped:'按设置跳过',failed:'未完成',cancelled:'已取消','not-run':'未执行'};if(!job){$('#workspace-status').textContent='尚未开始。先选主题，再点击启动。';document.querySelectorAll('[data-workspace-step]').forEach(el=>{el.dataset.state='pending';el.querySelector('span').textContent='待开始';});}if(job){$('#workspace-status').textContent=job.message;for(const step of job.steps){const el=document.querySelector('[data-workspace-step="'+step.id+'"]');if(el){el.dataset.state=step.state;el.querySelector('span').textContent=labels[step.state]??step.state;}}if(changed)message(job.message,job.state==='running'?'busy':job.state==='succeeded'?'success':job.state==='partial'?'partial':job.state==='failed'?'error':'info');}lockWorkspaceControls();}

$('#workspace-start').onclick=()=>action($('#workspace-start'),async()=>{await api('settings',settings);renderWorkspace((await api('workspace/start',{})).job);});

$('#workspace-cancel').onclick=()=>action($('#workspace-cancel'),async()=>{if(!workspaceJob)throw Error('当前没有可取消的启动任务。');renderWorkspace((await api('workspace/cancel',{id:workspaceJob.id})).job);});

setInterval(async()=>{if(workspaceJob?.state!=='running'||pollingWorkspace||document.hidden||Date.now()<nextWorkspacePoll)return;pollingWorkspace=true;try{const previous=workspaceJob.state;renderWorkspace((await api('workspace')).job);if(previous==='running'&&workspaceJob?.state!=='running'){await refresh();}}catch(error){nextWorkspacePoll=Date.now()+5000;if(error.offline)offline(error.message);else message(error.message,'error');}finally{pollingWorkspace=false;}},1000);

api('workspace').then(result=>renderWorkspace(result.job)).catch(()=>{});

refresh(true).then(()=>{if(workspaceJob?.state!=='running')message($('#connection').textContent+'；'+$('#applied').textContent);}).catch(error=>{if(error.offline)offline(error.message);else{$('#connection').textContent='桌面连接检查失败';$('#applied').textContent='更换状态：无法核验';message('检测未完成：'+error.message,'error');}});

setInterval(async()=>{if(stale||busy||document.hidden)return;try{const r=await fetch('/health',{signal:AbortSignal.timeout(2500)});if(!r.ok)throw Error();const health=await r.json();if(health.version!==clientVersion)requireReload(health.version);}catch{offline('本地后台已断开，当前页面仅保留预览，无法执行桌面操作。');}},10000);

let refreshing=false;setInterval(async()=>{if(stale||busy||refreshing||document.hidden||workspaceJob?.state==='running')return;refreshing=true;try{await refresh();}catch(error){if(error.offline)offline(error.message);}finally{refreshing=false;}},8000);

$('#background-motion').onchange=()=>{settings.motion=$('#background-motion').checked;preview();message('动效预览已更新，点击保存或应用到桌面以保留设置。');};



document.querySelectorAll('[data-pet]').forEach(button=>button.onclick=()=>action(button,async()=>{const result=await api('pet-theme',{petId:button.dataset.pet});settings.petId=result.petId;sync();await refresh();message(result.message);}));

$('#boot-sound').onchange=()=>saveModuleFlag('bootSound','#boot-sound');

