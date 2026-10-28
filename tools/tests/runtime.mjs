import path from 'node:path';import {fileURLToPath} from 'node:url';import fs from 'node:fs/promises';
export const projectRoot=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
export const sourceRoot=path.join(projectRoot,'sakura-studio');export const reportsRoot=path.join(projectRoot,'reports');await fs.mkdir(reportsRoot,{recursive:true});
let runtime;try{runtime=await import('playwright')}catch{}
export const chromium=runtime?.chromium;export const edgePath=process.env.SAKURA_TEST_BROWSER??path.join(process.env['ProgramFiles(x86)']??'C:/Program Files (x86)','Microsoft/Edge/Application/msedge.exe');
