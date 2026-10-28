import fs from 'node:fs/promises';

export async function writeBootSignals(receipt,target,ready){
  const targetFile=receipt+'.target',readyFile=receipt+'.desktop-ready';
  const next=target?String(target.handle)+' '+String(target.pid):null;
  let previous=null;try{previous=await fs.readFile(targetFile,'utf8');}catch(error){if(error.code!=='ENOENT')throw error;}
  // Revoke permission before switching native window identities.
  if(!ready||next!==previous)await fs.rm(readyFile,{force:true});
  if(next!==previous){
    if(next===null)await fs.rm(targetFile,{force:true});
    else{await fs.writeFile(targetFile+'.tmp',next);await fs.rename(targetFile+'.tmp',targetFile);}
  }
  if(ready&&next!==null){try{await fs.access(readyFile);}catch{await fs.writeFile(readyFile,'ready');}}
}

export async function watchBootReadiness({active,inspect,shell,publish,sleep=ms=>new Promise(resolve=>setTimeout(resolve,500))}){
  while(active()){
    try{
      const connection=await inspect();if(!active())return;
      const target=connection.owned&&connection.connected?connection.window:null;
      const ready=!!target&&target.visible===true&&(await shell(connection)).ready===true;
      if(!active())return;
      await publish(target,ready);
    }catch{if(active())await publish(null,false).catch(()=>{});}
    if(active())await sleep();
  }
}
