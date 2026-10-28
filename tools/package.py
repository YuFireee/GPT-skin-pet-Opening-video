from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parent.parent
APP=ROOT/'sakura-studio'
VERSION=json.loads((ROOT/'package.json').read_text(encoding='utf-8'))['version']
def sha(p):
 with p.open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
local=APP/'materials.local.json'
if not local.is_file():raise SystemExit('Import external materials using tools/prepare.ps1 before local packaging.')
for entry in json.loads(local.read_text(encoding='utf-8'))['entries']:
 target=(APP/entry['target']).resolve()
 assert target.is_relative_to(APP.resolve()),'Material target outside app'
 if not target.is_file() or sha(target)!=entry['sha256']:raise SystemExit('Run prepare.cmd before packaging: '+entry['target'])
for name in ['SakuraBoot.exe','SakuraVisual.exe','SakuraControl.exe']:
 if not (APP/name).is_file():raise SystemExit('Run prepare.cmd to compile native windows first.')
files=sorted(p for p in APP.rglob('*') if p.is_file() and 'state' not in p.relative_to(APP).parts and p.name not in {'build-info.json','materials.local.json'})
manifest={'version':VERSION,'files':{p.relative_to(APP).as_posix():sha(p) for p in files}}
(APP/'build-info.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
dest=ROOT/'releases'/f'sakura-studio-{VERSION}-LOCAL-ONLY.zip';dest.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,6) as z:
 for p in [*files,APP/'build-info.json']:z.write(p,'sakura-studio/'+p.relative_to(APP).as_posix())
with zipfile.ZipFile(dest) as z:
 assert z.testzip() is None
 assert all('/state/' not in n for n in z.namelist())
 for name,h in manifest['files'].items():assert hashlib.sha256(z.read('sakura-studio/'+name)).hexdigest()==h
dest.with_suffix('.zip.sha256').write_text(sha(dest)+'  '+dest.name+'\n',encoding='ascii')
print(json.dumps({'release':str(dest),'files':len(files)+1,'bytes':dest.stat().st_size}))
