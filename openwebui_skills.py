#!/usr/bin/env python3
"""Import complete skill packages using Open WebUI v0.13.4's authenticated API.
Full repositories remain on disk. Never deletes OMP or old skill copies.
"""
import argparse, base64, getpass, hashlib, json, os, pathlib, subprocess, sys, stat, urllib.error, urllib.parse, urllib.request, uuid
REPOS = {
 'scientific-agent-skills': 'https://github.com/K-Dense-AI/scientific-agent-skills.git',
 'claude-scientific-writer': 'https://github.com/K-Dense-AI/claude-scientific-writer.git',
 'education-agent-skills': 'https://github.com/GarethManning/education-agent-skills.git',
}
REVISIONS = {
 'scientific-agent-skills':'ec59a29a03d5c40f73ab40878df04860bc00e876',
 'claude-scientific-writer':'9820740d252800ecf0b8fc066ffb5bf9659f4a51',
 'education-agent-skills':'135d6275e7db0657d70b147f46d3191c5430677d',
}
def linked(path):
 try:
  st=path.lstat()
  return stat.S_ISLNK(st.st_mode) or bool(getattr(st,'st_file_attributes',0)&0x400)
 except FileNotFoundError:return False
def safe_walk(root):
 for current,dirs,names in os.walk(root,followlinks=False):
  if '.git' in dirs:dirs.remove('.git')
  for name in dirs+names:
   if linked(pathlib.Path(current)/name):raise ValueError('Linked/reparse repository entry refused: '+str(pathlib.Path(current)/name))
  yield pathlib.Path(current),dirs,names
def git(*args):
 return subprocess.check_output(['git', *map(str,args)], text=True).strip()
def prepare(root):
 if any(linked(p) for p in (root,*root.parents)): raise ValueError('Refusing linked repository root')
 root.mkdir(parents=True, exist_ok=True)
 for name,url in REPOS.items():
  dest=root/name
  if linked(dest): raise ValueError('Refusing linked repository: '+str(dest))
  if dest.exists():
   if git('-C',dest,'remote','get-url','origin')!=url: raise ValueError('Different repository preserved: '+str(dest))
   print('Keeping existing complete checkout:',dest)
  else:
   subprocess.run(['git','clone','--',url,str(dest)],check=True)
   if name in REVISIONS:git('-C',dest,'checkout','--detach',REVISIONS[name])
  if subprocess.run(['git','-C',str(dest),'config','--get','core.sparseCheckout'],capture_output=True,text=True).stdout.strip()=='true': raise ValueError('Sparse checkout is not a complete repository')
 return inventory(root)
def hash_files(files):
 return {f['path']:hashlib.sha256(base64.b64decode(f['content']) if f.get('encoding')=='base64' else f['content'].encode()).hexdigest() for f in files}
def inventory(root):
 if any(linked(p) for p in (root,*root.parents)): raise ValueError('Refusing linked repository root')
 packages=[]
 for name,url in REPOS.items():
  repo=root/name
  if not repo.is_dir() or linked(repo): raise ValueError('Missing or linked complete repository: '+str(repo))
  if git('-C',repo,'remote','get-url','origin')!=url: raise ValueError('Unexpected repository origin: '+name)
  sparse=subprocess.run(['git','-C',str(repo),'config','--get','core.sparseCheckout'],capture_output=True,text=True).stdout.strip()
  if sparse=='true':raise ValueError('Sparse checkout cannot verify the complete skill migration: '+name)
  if git('-C',repo,'status','--porcelain'): raise ValueError('Locally changed repository preserved; refusing to import unexpected files: '+name)
  revision=git('-C',repo,'rev-parse','HEAD')
  if name in REVISIONS and revision!=REVISIONS[name]:raise ValueError('Different repository revision preserved; audited source required: '+name)
  roots=[]
  markers=sorted(current/'SKILL.md' for current,dirs,names in safe_walk(repo) if 'SKILL.md' in names)
  for marker in markers:
   directory=marker.parent
   if any(directory.is_relative_to(parent) for parent in roots): continue
   roots.append(directory)
  if not roots: raise ValueError('No skill definitions discovered: '+name)
  for directory in roots:
   files=[]; total=0
   for current, dirs, names in safe_walk(directory):
    for filename in sorted(names):
     path=pathlib.Path(current)/filename
     rel=path.relative_to(directory).as_posix()
     if ':' in rel or '\\' in rel: raise ValueError('Unsupported skill path: '+rel)
     st=path.stat()
     if not stat.S_ISREG(st.st_mode):raise ValueError('Nonregular skill file refused: '+str(path))
     size=st.st_size; total+=size
     if size>10*1024**2 or total>50*1024**2: raise ValueError('Open WebUI size limit exceeded; nothing omitted: '+str(directory))
     data=path.read_bytes()
     try:
      text=data.decode('utf-8')
      if '\0' in text: raise UnicodeError()
      files.append({'path':rel,'content':text})
     except UnicodeError: files.append({'path':rel,'content':base64.b64encode(data).decode(),'encoding':'base64'})
   if len(files)>1000: raise ValueError('Open WebUI file limit exceeded: '+str(directory))
   relative=directory.relative_to(repo).as_posix()
   ident='pc-setup-'+hashlib.sha256((url+'#'+relative).encode()).hexdigest()[:32]
   packages.append({'id':ident,'name':name+' / '+relative,'files':sorted(files,key=lambda x:x['path']),'meta':{'tags':['pc-setup','source:'+url,'revision:'+revision,'directory:'+relative],'i18n':None},'is_active':True})
 if set(REPOS)==set(REVISIONS) and (len(packages)!=422 or sum(len(p['files']) for p in packages)!=3968):
  raise ValueError('Audited complete skill inventory differs from 422 definitions / 3968 files; old installation retained')
 return packages
class API:
 def __init__(self,url):
  parsed=urllib.parse.urlsplit(url)
  if parsed.scheme!='http' or parsed.hostname not in ('127.0.0.1','localhost','::1') or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ('','/'):
   raise ValueError('Use a loopback HTTP Open WebUI URL, without credentials or path')
  self.url=url.rstrip('/'); self.token=None
 def request(self,path,body=None,content_type='application/json'):
  headers={'Content-Type':content_type}
  if self.token:headers['Authorization']='Bearer '+self.token
  req=urllib.request.Request(self.url+path,data=body,headers=headers)
  # Do not forward local credentials to redirect destinations.
  class NoRedirect(urllib.request.HTTPRedirectHandler):
   def redirect_request(self,*args,**kwargs): return None
  with urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect).open(req,timeout=120) as response:return json.load(response)
 def signin(self,email,password):
  result=self.request('/api/v1/auths/signin',json.dumps({'email':email,'password':password}).encode())
  self.token=result.get('token')
  if not self.token:raise ValueError('Sign-in requires additional authentication; finish sign-in in Open WebUI first')
 def multipart(self,path,package,decisions=None):
  boundary='pcsetup'+uuid.uuid4().hex
  parts=[f'--{boundary}\r\nContent-Disposition: form-data; name="files"; filename="skill.json"\r\nContent-Type: application/json\r\n\r\n'.encode()+json.dumps(package).encode()+b'\r\n']
  if decisions is not None:parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="decisions"\r\n\r\n'.encode()+json.dumps(decisions).encode()+b'\r\n')
  parts.append(f'--{boundary}--\r\n'.encode())
  return self.request(path,b''.join(parts),'multipart/form-data; boundary='+boundary)
def verify(api,package):
 exported=api.request('/api/v1/skills/export?format=json&ids='+urllib.parse.quote(package['id']))
 remote=exported if isinstance(exported,dict) else (exported[0] if isinstance(exported,list) and len(exported)==1 else {})
 if remote.get('id')!=package['id']:raise ValueError('Unexpected skill readback')
 if hash_files(remote['files'])!=hash_files(package['files']) or remote.get('name')!=package['name'] or remote.get('meta')!=package['meta'] or not remote.get('is_active'):
  raise ValueError('Existing/remote skill differs; preserved, not overwritten: '+package['name'])
def import_all(api,packages):
 for package in packages:
  preview=api.multipart('/api/v1/skills/import/preview',package)
  if not isinstance(preview,list) or len(preview)!=1 or preview[0]['id']!=package['id']:raise ValueError('Unexpected import preview')
  if preview[0]['id_taken']:verify(api,package)
  else:
   if preview[0]['name_taken']:raise ValueError('Existing skill name conflict; preserved: '+package['name'])
   result=api.multipart('/api/v1/skills/import',package,[{'action':'create'}])
   if not isinstance(result,list) or len(result)!=1 or result[0].get('status')!='saved' or result[0].get('id')!=package['id']:raise ValueError('Skill import did not save: '+package['name'])
   verify(api,package)
  print('Verified all file bytes:',package['name'])
 # Second complete readback prevents a partial run from being called a complete migration.
 for package in packages: verify(api,package)
def verify_reference(manifest):
 record=json.loads(manifest.read_text(encoding='utf-8-sig'))
 archive=pathlib.Path(record['archive']);expected=str(record['sha256']).lower()
 if len(expected)!=64 or any(c not in '0123456789abcdef' for c in expected):raise ValueError('Invalid Wikipedia checksum record')
 if not archive.is_file() or archive.suffix.lower()!='.zim':raise ValueError('Verified Wikipedia archive is missing')
 print('Rechecking the complete Wikipedia archive SHA-256 before migration; this can take several minutes.',flush=True)
 digest=hashlib.sha256()
 with archive.open('rb') as source:
  while block:=source.read(8*1024*1024):digest.update(block)
 if digest.hexdigest()!=expected:raise ValueError('Wikipedia archive checksum changed; existing OMP/data retained')
 print('Wikipedia archive bytes match the installer verification record.')
def main():
 parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('action',choices=['prepare','import','verify']);parser.add_argument('--root',type=pathlib.Path,required=True);parser.add_argument('--url',default='http://127.0.0.1:8080');parser.add_argument('--wiki-key-file',type=pathlib.Path);parser.add_argument('--reference-manifest',type=pathlib.Path);args=parser.parse_args()
 packages=prepare(args.root) if args.action=='prepare' else inventory(args.root)
 print('Discovered',len(packages),'complete skill packages across all three repositories.')
 if args.action=='prepare':print('Repositories prepared only. Create/sign in to your local Open WebUI account, then run import. Old skills must remain.');return
 if args.reference_manifest:verify_reference(args.reference_manifest)
 api=API(args.url);api.signin(input('Local Open WebUI account email: ').strip(),getpass.getpass('Local Open WebUI password (not saved): '))
 if args.action=='import':
  import_all(api,packages)
  if args.wiki_key_file:
   from openwebui_connections import configure
   configure(api,args.wiki_key_file,'qwen-image-2.1-colibri')
 else:
  for package in packages:verify(api,package)
 print('All packages verified in Open WebUI. Full repositories and old skills were retained. Skill instructions/assets are available; this does not install their optional external services or executable tools.')
if __name__=='__main__':
 try:main()
 except (ValueError,OSError,subprocess.CalledProcessError,KeyError) as error:
  print('Skill setup stopped; old files were not removed:',str(error),file=sys.stderr);sys.exit(1)
