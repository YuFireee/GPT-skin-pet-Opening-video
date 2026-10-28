import {randomBytes} from 'node:crypto';

class Cancelled extends Error {}

export function createWorkspaceController(deps){
  let current=null;
  const active=()=>current?.state==='running';
  const snapshot=()=>current?{
    id:current.id,state:current.state,phase:current.phase,message:current.message,
    startedAt:current.startedAt,finishedAt:current.finishedAt,themeId:current.config.themeId,
    steps:current.steps.map(step=>({...step})),warnings:[...current.warnings],cancelRequested:current.cancelRequested,
  }:null;
  function check(job){if(job.cancelRequested)throw new Cancelled();}
  function step(job,id,state,message){
    job.steps.find(item=>item.id===id).state=state;job.phase=id;if(message)job.message=message;
  }
  async function run(job){
    let opening=null;
    try{
      if(job.config.boot){
        step(job,'boot','running','正在显示启动开场…');
        try{opening=await deps.beginBoot(job.config);}
        catch(error){job.warnings.push('开场未完成：'+error.message);step(job,'boot','failed');}
        check(job);
      }else step(job,'boot','skipped');
      step(job,'desktop','running','正在准备独立桌面窗口…');
      const initial=await deps.connection();check(job);
      if((!initial.connected&&!initial.window)||initial.window?.visible===false||initial.window?.minimized===true){const launch=await deps.launch(job.config);if(!launch.started)throw Error(launch.reason||'桌面窗口未能启动');}
      step(job,'desktop','complete',initial.connected?'复用已连接的桌面窗口。':'独立桌面窗口已准备，稍后核验连接。');
      check(job);
      if(opening){
        step(job,'boot','running','正在播放启动开场…');
        try{await opening.finished;step(job,'boot','complete');}
        catch(error){job.warnings.push('开场未完成：'+error.message);step(job,'boot','failed');}
      }
      check(job);
      step(job,'theme','running','正在等待桌面连接与主界面；首次使用可能需要登录…');
      const now=deps.now??Date.now,sleep=deps.sleep??(ms=>new Promise(resolve=>setTimeout(resolve,ms)));
      const deadline=now()+90000;let applied=false,lastReason='桌面主界面未就绪';
      while(now()<deadline){
        check(job);const c=await deps.connection();check(job);
        if(c.connected){
          try{
            const result=await deps.apply(job.config,c);
            if(!result?.verification?.rendered||result.verification.themeId!==job.config.themeId)throw Error('主题渲染结果未确认，不能报告启动完成。');
            if(!result.window?.pageVisible)job.warnings.push('主题已加载，但主界面显示未确认，请点击“显示已换肤窗口”或从任务栏选中专用窗口。');
            else if(!result.window.foreground)job.warnings.push('主题页面可见，但前台激活未确认。');
            step(job,'theme','complete','主题已加载，正在确认附加模块。');applied=true;break;
          }
          catch(error){
            if(!/未识别到桌面主界面|未识别到桌面主界面和侧栏|Execution context was destroyed|Cannot find context/.test(error.message))throw error;
            lastReason='窗口已连接，正在等待可换肤的主界面';
          }
        }else lastReason=c.reason||lastReason;
        job.message=lastReason+'。请保持独立窗口打开；可以取消后续步骤。';
        await sleep(1000);
      }
      if(!applied)throw Error('等待主界面超时，未报告主题成功。完成登录或打开主界面后可重新启动。');
      check(job);
      step(job,'companion','running',job.config.companion?'正在显示角色小窗…':'正在按设置关闭角色小窗…');
      try{await deps.ensureCompanion(job.config.companion,job.config);step(job,'companion',job.config.companion?'complete':'skipped');}
      catch(error){job.warnings.push('角色小窗未完成：'+error.message);step(job,'companion','failed');}
      check(job);
      job.state=job.warnings.length?'partial':'succeeded';
      job.message=job.warnings.length?'部分完成：'+job.warnings.join('；'):'工作空间已就绪：主题、主窗口显示和已开启模块均已确认。';
    }catch(error){
      if(error instanceof Cancelled){job.state='cancelled';job.message='已取消后续启动步骤；已完成的步骤保留，桌面窗口不会被退出。';}
      else{job.state='failed';job.message=error.message;const running=job.steps.find(item=>item.state==='running');if(running)running.state='failed';}
    }finally{
      if(opening)await opening.stop().catch(()=>{});
      for(const item of job.steps)if(item.state==='running'||item.state==='pending')item.state=job.state==='cancelled'?'cancelled':'not-run';
      job.finishedAt=new Date().toISOString();
    }
  }
  return {
    active,snapshot,
    start(config){
      if(active())throw Error('一键启动仍在进行，请等待完成或取消。');
      const job={id:randomBytes(12).toString('hex'),state:'running',phase:'desktop',message:'启动任务已创建。',config:{...config},startedAt:new Date().toISOString(),finishedAt:null,cancelRequested:false,warnings:[],steps:[{id:'desktop',label:'桌面窗口',state:'pending'},{id:'boot',label:'启动开场',state:'pending'},{id:'theme',label:'应用主题',state:'pending'},{id:'companion',label:'角色小窗',state:'pending'}]};
      current=job;job.promise=run(job);return snapshot();
    },
    cancel(id){
      if(!active())return snapshot();
      if(id!==current.id)throw Error('启动任务已变化，请刷新后重试。');
      current.cancelRequested=true;current.message='正在停止后续步骤；当前已开始的操作结束后停止。';return snapshot();
    },
  };
}
