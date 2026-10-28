"""Export only Git-visible source files; never account state or generated assets."""
from pathlib import Path
import hashlib,subprocess,zipfile,json
ROOT=Path(__file__).resolve().parent.parent
result=subprocess.run(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT,capture_output=True,check=True)
names=sorted(set(n.decode('utf-8') for n in result.stdout.split(b'\0') if n))
assert names,'No source files found; initialize this directory as a Git repository first.'
assert '.gitignore' in names and 'sakura-studio/quota-pet/.codex-plugin/plugin.json' in names
for name in names:
 p=ROOT/name;assert p.resolve().is_relative_to(ROOT) and not p.is_symlink()
 assert not any(part in {'.git','node_modules','state','desktop-profile','reports','releases'} for part in p.relative_to(ROOT).parts),name
 assert p.suffix.lower() not in {'.exe','.dll','.pdb','.log','.zip'},name
 assert p.name not in {'auth.json','installation.json','materials.local.json','.env','.npmrc'},name
 assert p.suffix.lower() not in {'.png','.jpg','.jpeg','.webp','.gif','.ico','.mp4','.webm','.mov','.mkv','.avi','.wav','.mp3','.ogg','.flac'},'Local-only media in public source: '+name
dest=ROOT/'releases/sakura-studio-github-source.zip';dest.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,6) as z:
 for name in names:z.write(ROOT/name,'sakura-studio-github/'+name)
with zipfile.ZipFile(dest) as z:assert z.testzip() is None
with dest.open('rb') as f:h=hashlib.file_digest(f,'sha256').hexdigest()
dest.with_suffix('.zip.sha256').write_text(h+'  '+dest.name+'\n',encoding='ascii')
print(json.dumps({'fileCount':len(names),'bytes':dest.stat().st_size,'sha256':h,'file':str(dest)}))
