import fs from 'node:fs/promises';import path from 'node:path';import {fileURLToPath} from 'node:url';import {createHash} from 'node:crypto';import {spawnSync} from 'node:child_process';import assert from 'node:assert/strict';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),app=path.join(root,'sakura-studio'),reports=path.join(root,'reports');

const hash=b=>createHash('sha256').update(b).digest('hex');

async function json(p){return JSON.parse((await fs.readFile(p,'utf8')).replace(/^\uFEFF/,''))}

async function walk(dir){let files=[];for(const e of await fs.readdir(dir,{withFileTypes:true})){if(['node_modules','reports','releases','.git'].includes(e.name))continue;const p=path.join(dir,e.name);if(e.isSymbolicLink())throw Error('Linked file in upload directory: '+path.relative(root,p));files.push(...(e.isDirectory()?await walk(p):[p]))}return files}

const runtimeMode=process.argv.includes('--runtime');

const publicManifest=await json(path.join(root,'materials/manifest.json'));

assert.equal(publicManifest.distribution,'public-code-only');

const manifest=runtimeMode?await json(path.join(app,'materials.local.json')):publicManifest;const seen=new Set();let materials=0;

for(const e of manifest.entries){

 const source=path.resolve(root,'materials',e.source),target=path.resolve(app,e.target);

 assert(source.startsWith(path.join(root,'materials')+path.sep)&&target.startsWith(app+path.sep),'Asset path traversal');assert(!seen.has(e.target),'Duplicate material target');seen.add(e.target);

 if(runtimeMode)assert.equal(hash(await fs.readFile(target)),e.sha256,'Prepare the app before auditing: '+e.target);

 else{assert.equal(e.bundled,false);assert.equal(await fs.access(source).then(()=>true,()=>false),false,'Local material in public source folder: '+e.source)}

 materials++;

}

const all=await walk(root);let javascript=0,jsonFiles=0,imports=0;

for(const file of all){

 const rel=path.relative(root,file).replaceAll(path.sep,'/');

 const generated=rel==='sakura-studio/materials.local.json'||rel.startsWith('sakura-studio/assets/')||rel.startsWith('sakura-studio/quota-pet/assets/')||rel==='sakura-studio/quota-pet/preview.png';

 if(generated)continue;

 assert(!rel.split('/').some(p=>['state','desktop-profile'].includes(p)),'Private data directory');assert(!['auth.json','installation.json','.env','.npmrc'].includes(path.basename(file)),'Local configuration leaked');

 assert(!/\.(png|jpe?g|webp|gif|ico|mp4|webm|mov|mkv|avi|wav|mp3|ogg|flac)$/i.test(file),'Media file in public upload directory: '+rel);

 const size=(await fs.stat(file)).size;assert(size<95*1024*1024,'File too large for ordinary Git hosting: '+rel);

 if(!['.mjs','.js','.cs','.ps1','.cmd','.json','.html','.css','.md','.txt','.yml'].includes(path.extname(file)))continue;

 const text=(await fs.readFile(file,'utf8')).replace(/^\uFEFF/,'');

 if(!rel.startsWith('tools/'))assert(!/[CD]:[\\/](?:Users[\\/]|picture[\\/]|QQ)/i.test(text),'Machine-specific absolute path: '+rel);

 const keyLike=/(?:ghp_[a-zA-Z0-9]{30,}|github_pat_[a-zA-Z0-9_]{40,}|sk-(?:proj-)?[a-zA-Z0-9_-]{32,}|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----)/;

 assert(!keyLike.test(text),'Potential credential: '+rel);

 if(file.endsWith('.json')){JSON.parse(text);jsonFiles++}

 if(/\.(mjs|js)$/.test(file)){

  const result=spawnSync(process.execPath,['--check',file],{encoding:'utf8'});assert.equal(result.status,0,rel+'\n'+result.stderr);javascript++;

  for(const match of text.matchAll(/(?:\bfrom\s*|\bimport\s*\(\s*|\bimport\s*)['"](\.[^'"]+)['"]/g)){const target=path.resolve(path.dirname(file),match[1]);await fs.access(target);imports++}

 }

}

const plugin=await json(path.join(app,'quota-pet/.codex-plugin/plugin.json'));assert(!plugin.mcpServers,'Integrated build must not advertise an absent MCP registration');

async function existsOrExternal(file){const absolute=path.resolve(file);if(!runtimeMode&&absolute===path.join(app,'quota-pet/runtime/WidgetNative.dll')){await fs.access(path.join(app,'build-pet-native.ps1'));return;}if(!runtimeMode&&absolute===path.join(app,'quota-pet/runtime/VideoFullscreenProbe.exe')){await fs.access(path.join(app,'quota-pet/runtime/VideoFullscreenProbe.cs'));return;}if(!runtimeMode&&seen.has(path.relative(app,absolute).replaceAll(path.sep,'/')))return;await fs.access(absolute)}

for(const file of await json(path.join(app,'quota-pet/runtime/install-files.json')))await existsOrExternal(path.join(app,'quota-pet',file));

for(const key of ['composerIcon','logo'])await existsOrExternal(path.resolve(app,'quota-pet',plugin.interface[key]));

assert.equal((await json(path.join(root,'package.json'))).version,'0.9.6');

const report={passed:true,version:'0.9.6',mode:runtimeMode?'local-runtime':'public-source',externalMaterialSlots:materials,javascriptFiles:javascript,jsonFiles,relativeImports:imports,checks:[runtimeMode?'Generated local material SHA-256 verified':'Required media absent from public sources; external material slots declared','Relative JavaScript imports and syntax','JSON and integrated vendor file manifest','Missing MCP metadata removed','No detected account state, private keys or machine-specific source paths','All source files below 95 MiB'],scope:'Static checks; credential pattern scan is not a proof of absence of all possible secrets'};

await fs.mkdir(reports,{recursive:true});await fs.writeFile(path.join(reports,'source-audit.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));

