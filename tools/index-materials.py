"""Index personally authorized material files in an external, untracked directory."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parent.parent
if len(sys.argv)!=2:raise SystemExit('Usage: python tools/index-materials.py EXTERNAL_DIRECTORY')
directory=Path(sys.argv[1]).expanduser().resolve()
if directory==ROOT or directory.is_relative_to(ROOT):raise SystemExit('Materials must be outside the public repository.')
template=json.loads((ROOT/'materials/manifest.json').read_text(encoding='utf-8'))
entries=[]
for entry in template['entries']:
 p=(directory/entry['source']).resolve()
 if not p.is_relative_to(directory) or not p.is_file():raise SystemExit('Missing external material: '+entry['source'])
 with p.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
 entries.append({'source':entry['source'],'target':entry['target'],'bytes':p.stat().st_size,'sha256':digest})
dest=directory/'manifest.json'
metadata=json.loads(dest.read_text(encoding='utf-8')) if dest.is_file() else {}
result={'schema':1,'entries':entries}
if metadata.get('openingOverlay')=='petals-only':result['openingOverlay']='petals-only'
dest.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Indexed '+str(len(entries))+' local material files. This does not grant redistribution rights.')
