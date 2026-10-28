// A topmost opening can occlude Chromium and make document.visibilityState hidden.
// Native visibility and laid-out shell elements determine readiness independently.
export function bootDesktopReady(connection,shell){
  return connection.owned===true&&connection.connected===true&&connection.window?.visible===true&&connection.window?.minimized===false&&shell?.ready===true;
}
export function bootShellStatus(selectors){
  const hasLayout=(selector,width,height)=>[...document.querySelectorAll(selector)].some(element=>{const bounds=element.getBoundingClientRect();return bounds.width>=width&&bounds.height>=height;});
  return {ready:document.readyState!=='loading'&&hasLayout(selectors['left-panel'],1,1)&&hasLayout(selectors['shell-main'],300,200)};
}
