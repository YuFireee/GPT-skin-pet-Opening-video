export async function applySkin(config) {
  const key='__SAKURA_STUDIO_V1__';
  if(document.documentElement.hasAttribute('data-dream-skin'))throw Error('请先暂停其他换肤工具，再应用樱色工坊。');
  const findMain=()=>[...document.querySelectorAll(config.selectors['shell-main'])].find(node=>node.getClientRects().length&&node.clientWidth>0&&node.clientHeight>0);
  let main=findMain();
  const sidebar=document.querySelector(config.selectors['left-panel']);
  if(!main||!sidebar)throw Error('当前页面未识别到桌面主界面和侧栏，未应用任何修改。');
  const image=new Image();image.src=config.image;
  await image.decode();
  if(!image.naturalWidth||!image.naturalHeight)throw Error('背景图片解码失败，未更换主题。');
  main=findMain();if(!main)throw Error('当前主界面正在切换，未应用修改；请稍后重试。');
  window[key]?.cleanup();
  const original=new Map();
  const mark=(node,part)=>{if(!original.has(node))original.set(node,node.getAttribute('data-sakura-part'));if(node.getAttribute('data-sakura-part')!==part)node.setAttribute('data-sakura-part',part);};
  const bind=()=>{
    for(const [part,selector] of Object.entries(config.parts))for(const node of document.querySelectorAll(selector)){
      if(part==='message'&&node.parentElement?.closest(selector))continue;
      const userMessage=part==='message'&&(node.matches('[data-message-author-role="user"], [data-local-conversation-user-anchor]')||node.querySelector('[data-message-author-role="user"], [data-local-conversation-user-anchor]'));
      mark(node,userMessage?'user-message':part);
    }
    const currentMain=findMain();
    for(let node=currentMain?.parentElement;node&&node!==document.body;node=node.parentElement)mark(node,node.matches('[class*="_ApplicationMenuPageSurfaceLayout_"]')?'frame':'shell');
    for(const node of original.keys())if(!node.isConnected){const value=original.get(node);if(value===null)node.removeAttribute('data-sakura-part');else node.setAttribute('data-sakura-part',value);original.delete(node);}
  };
  const rule=(part,value)=>`[data-sakura-part="${part}"]{${value}}`;
  const panel=(alpha)=>`background:rgba(35,25,40,${alpha}) !important;border-color:rgba(208,184,213,.12) !important;box-shadow:none !important;backdrop-filter:none !important;color:#f5f1f7 !important;`;
  const style=document.createElement('style');style.id='sakura-studio-style';
  let motion=null;
  const createMotion=()=>{
    const motion=document.createElement('div');motion.id='sakura-motion';motion.setAttribute('aria-hidden','true');motion.inert=true;
    const sun=document.createElement('div');sun.className='sakura-sunlight';motion.append(sun);const halo=document.createElement('div');halo.className='sakura-sunhalo';motion.append(halo);
    const shade=document.createElement('div');shade.className='sakura-leafshade';motion.append(shade);
    for(let i=0;i<30;i++){const p=document.createElement('i');p.className='sakura-petal';p.style.cssText=`--x:${(i*43)%108-4}vw;--drift:${18+i%5*4}vw;--turn:${200+i*21}deg;--size:${i===4||i===15?23:6+i%5*2}px;--duration:${19+i%7*3}s;--delay:-${i*2.73}s;--alpha:${.25+i%4*.08};`;motion.append(p);}
    return motion;
  };
  const menuTint=`rgba(35,25,40,${1-(config.menubar??12)/100})`;
  style.textContent=`body{isolation:isolate;background: #211529 url("${config.image}") ${config.focusX*100}% center / cover fixed no-repeat !important;}`+
    `#sakura-motion{position:fixed;inset:0;z-index:-1;overflow:hidden;pointer-events:none!important;user-select:none;}#sakura-motion *{pointer-events:none!important;}#sakura-motion .sakura-petal{position:absolute;left:var(--x);top:-8vh;width:var(--size);height:calc(var(--size)*.65);border-radius:80% 12% 75% 15%;background:linear-gradient(120deg,#fff0f5,#e6a3bf);opacity:var(--alpha);animation:sakura-fall var(--duration) linear var(--delay) infinite;will-change:transform;}@keyframes sakura-fall{from{transform:translate3d(0,-8vh,0) rotate(0)}to{transform:translate3d(var(--drift),118vh,0) rotate(var(--turn))}}#sakura-motion .sakura-leafshade{position:absolute;inset:-4%;pointer-events:none;mask-image:radial-gradient(ellipse 50% 75% at 24% 48%,#000 20%,transparent 95%);}#sakura-motion .sakura-sunlight{position:absolute;left:-3vw;top:-4vh;width:120vw;height:140vh;pointer-events:none;transform-origin:0 0;background:conic-gradient(from 90deg at 0 0,transparent 0deg 13deg,rgba(255,244,214,.08) 17deg,rgba(255,245,220,.55) 22deg,rgba(255,242,208,.12) 27deg,transparent 32deg 35deg,rgba(255,243,210,.10) 39deg,rgba(255,248,226,.46) 44deg,rgba(255,242,208,.10) 49deg,transparent 54deg 57deg,rgba(255,244,214,.08) 61deg,rgba(255,248,226,.38) 66deg,rgba(255,242,208,.06) 71deg,transparent 77deg 360deg);mask-image:radial-gradient(circle 84vmax at 0 0,#000 0%,#000 22%,rgba(0,0,0,.75) 48%,transparent 88%);mix-blend-mode:screen;opacity:.48;animation:sakura-sun-rotate 24s ease-in-out -8s infinite alternate;will-change:transform;}#sakura-motion .sakura-leafshade{background:radial-gradient(ellipse 15% 7% at 24% 25%,rgba(46,28,54,.27),transparent 82%),radial-gradient(ellipse 19% 9% at 30% 52%,rgba(46,28,54,.25),transparent 85%),radial-gradient(ellipse 18% 7% at 18% 76%,rgba(46,28,54,.25),transparent 85%);mix-blend-mode:multiply;opacity:.13;animation:sakura-shade 31s ease-in-out infinite alternate;}@keyframes sakura-sun-rotate{from{transform:rotate(-8deg);opacity:.44}to{transform:rotate(10deg);opacity:.52}}@keyframes sakura-shade{from{transform:translate3d(-1.1%,.5%,0) rotate(-1deg);opacity:.13}to{transform:translate3d(1.3%,-.6%,0) rotate(1deg);opacity:.29}}#sakura-motion .sakura-sunhalo{position:absolute;inset:0;pointer-events:none;background:radial-gradient(ellipse 30vw 30vh at 0% 0%,rgba(255,252,222,.72) 0%,rgba(255,236,192,.27) 27%,rgba(255,235,197,.08) 55%,transparent 82%);mix-blend-mode:screen;opacity:.23;animation:sakura-halo 29s ease-in-out infinite alternate;}@keyframes sakura-halo{from{opacity:.20;transform:translate3d(-.2%,0,0)}to{opacity:.33;transform:translate3d(.3%,.2%,0)}}@media(prefers-reduced-motion:reduce){#sakura-motion{display:none!important;}}`+
    rule('shell','background:transparent !important;')+rule('main','background:transparent !important;color:#f5f1f7 !important;')+
    rule('home','background:transparent !important;')+rule('thread','background:transparent !important;')+
    rule('sidebar',panel(1-config.sidebar/100))+rule('header',panel(1-config.header/100))+
    'aside.app-shell-left-panel .sidebar-navigation[class*="_ConversationSidebar_"]{background:transparent!important;border-radius:0!important;box-shadow:none!important;}'+
    rule('menubar',panel(1-(config.menubar??12)/100))+rule('rail',panel(1-(config.rail??35)/100))+
    rule('frame',`background:linear-gradient(to bottom,${menuTint} 0,${menuTint} calc(var(--app-shell-application-menu-height,36px) + var(--app-shell-titlebar-top-inset,8px)),transparent calc(var(--app-shell-application-menu-height,36px) + var(--app-shell-titlebar-top-inset,8px)),transparent calc(100% - 4px),${menuTint} calc(100% - 4px),${menuTint} 100%) !important;`)+
    '[data-sakura-part="frame"] [data-sakura-part="menubar"]{background:transparent !important;}'+
    rule('backdrop','background:transparent !important;background-image:none !important;box-shadow:none !important;')+
    rule('message',panel(1-config.message/100))+rule('composer',panel(1-config.composer/100))+
    rule('message','--sakura-card-gutter:clamp(8px,1vw,16px);box-sizing:border-box !important;width:calc(100% + var(--sakura-card-gutter) + var(--sakura-card-gutter)) !important;margin-inline:calc(0px - var(--sakura-card-gutter)) !important;padding:12px var(--sakura-card-gutter) !important;border-radius:18px !important;')+
    '[data-sakura-part="message"] [data-sakura-part="message"]{background:transparent !important;padding:0 !important;margin:0 !important;width:auto !important;}'+
    rule('composer','--sakura-composer-gutter:clamp(8px,1vw,16px);box-sizing:border-box !important;width:calc(100% + var(--sakura-composer-gutter) + var(--sakura-composer-gutter)) !important;margin-inline:calc(0px - var(--sakura-composer-gutter)) !important;border-radius:22px !important;')+
    '[data-sakura-part="composer"] [class*="_ComposerLayoutBody_"]{background-color:transparent !important;background-image:none !important;}'+
    rule('toolbar','background:transparent !important;color:#e9e0ef !important;')+rule('dialog',panel(.94));
  // Only native host-window activity controls decorative resources. Page blur
  // also happens for inputs, menus and embedded browsers inside the foreground app.
  let active=config.active!==false;
  const releaseMotion=()=>{
    if(!motion)return;
    for(const animation of motion.getAnimations({subtree:true}))animation.cancel();
    motion.remove();motion.replaceChildren();motion=null;
  };
  const setActivity=value=>{
    active=value===true;
    if(!active)releaseMotion();
    else if(config.motion!==false&&!motion){motion=createMotion();document.body.prepend(motion);}
    return {active};
  };
  const cleanup=()=>{observer.disconnect();clearTimeout(timer);releaseMotion();style.remove();for(const [node,value] of original){if(value===null)node.removeAttribute('data-sakura-part');else node.setAttribute('data-sakura-part',value);}original.clear();delete window[key];};
  let timer;
  const observer=new MutationObserver(records=>{if(timer||!records.some(record=>[...record.addedNodes,...record.removedNodes].some(node=>node.nodeType===1)))return;timer=setTimeout(()=>{timer=null;bind();},120);});
  try{
    bind();document.head.append(style);setActivity(active);observer.observe(document.body,{childList:true,subtree:true});
    if(getComputedStyle(main).backgroundColor!=='rgba(0, 0, 0, 0)')throw Error('样式未生效，已撤回修改。');
    window[key]={cleanup,setActivity,rendererVersion:4,themeId:config.themeId,imageLoaded:true,imageWidth:image.naturalWidth,imageHeight:image.naturalHeight,motion:config.motion!==false};
    return {applied:true,themeId:config.themeId,main:true,sidebar:true,parts:Object.fromEntries(Object.keys(config.parts).map(p=>[p,document.querySelectorAll(`[data-sakura-part="${p}"]`).length]))};
  }catch(error){cleanup();throw error;}
}

export function restoreSkin(){const state=window.__SAKURA_STUDIO_V1__;if(state)state.cleanup();return {restored:true,hadTheme:!!state};}
export function setSkinActivity(active){return window.__SAKURA_STUDIO_V1__?.setActivity(active)??{active:false};}
export function skinStatus(){const state=window.__SAKURA_STUDIO_V1__,main=[...document.querySelectorAll('[data-sakura-part=main]')].find(node=>node.getClientRects().length&&node.clientWidth>0&&node.clientHeight>0);const rendered=!!state&&state.imageLoaded===true&&!!document.querySelector('#sakura-studio-style')&&!!main&&getComputedStyle(main).backgroundColor==='rgba(0, 0, 0, 0)'&&getComputedStyle(document.body).backgroundImage.includes('data:image/png;base64,');return {active:rendered,rendererVersion:state?.rendererVersion??0,scriptPresent:!!state,rendered,imageLoaded:state?.imageLoaded===true,imageWidth:state?.imageWidth??null,imageHeight:state?.imageHeight??null,pageVisible:document.visibilityState==='visible',focused:document.hasFocus(),themeId:state?.themeId||null};}
