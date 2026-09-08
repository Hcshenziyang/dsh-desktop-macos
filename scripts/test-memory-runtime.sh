#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json,os,shutil,socket,subprocess,tempfile,time,urllib.request,urllib.error,uuid
from pathlib import Path
runtime=shutil.which('dsh');repo=Path.cwd()
plugin=Path(os.environ.get('DSH_MEMORY_MODULE',str(Path.home()/'.dsh/profiles/web/node_modules/dsh-native-memory/lib/index.mjs')))
if not runtime or not plugin.is_file():raise SystemExit('Install DSH and dsh-native-memory, or set DSH_MEMORY_MODULE for this optional integration test.')
with tempfile.TemporaryDirectory(prefix='dsh-memory-integration-') as temporary:
 root=Path(temporary);home=root/'dsh';home.mkdir();project=root/'project';project.mkdir();other=root/'other';other.mkdir();token=uuid.uuid4().hex+uuid.uuid4().hex
 with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
 patch=root/'test.yml';patch.write_text(json.dumps([{'insert':[
  {'id':'dsh-native-memory','name':str(plugin),'config':{'approvalWrites':False,'maxProfileEntries':2,'maxProfileEntryChars':40,'maxFactChars':100,'maxFactsPerWorkspace':3}},
  {'id':'project-memory','name':str(repo/'Resources/ProjectMemory/host.mjs'),'config':{'token':token}},
  {'id':'workspace-test','name':str(repo/'Tests/WorkspaceTools/runtime-fixture.mjs'),'config':{'token':token}}
 ]}]))
 base=f'http://127.0.0.1:{port}'
 def start():
  log=(root/'runtime.log').open('ab')
  p=subprocess.Popen([runtime,'web','--patch',str(patch),'--host','127.0.0.1','--port',str(port),'--no-open'],cwd=root,env=dict(os.environ,DSH_HOME=str(home),DSH_TELEMETRY_DISABLED='1'),stdout=log,stderr=log);log.close()
  for _ in range(150):
   if p.poll() is not None:raise RuntimeError('DSH exited: '+(root/'runtime.log').read_text()[-4000:])
   try:
    with urllib.request.urlopen(base+'/dsh-desktop/project-memory.js',timeout=1) as r:
     if r.status==200:return p
   except OSError:time.sleep(.2)
  p.terminate();p.wait();raise RuntimeError('Startup timeout')
 def stop(p):
  p.terminate()
  try:p.wait(timeout=10)
  except subprocess.TimeoutExpired:p.kill();p.wait()
 def request(path,payload,auth=True,origin=False):
  headers={'Content-Type':'application/json'}
  if auth:headers['Authorization']='Bearer '+token
  if origin:headers['Origin']=base
  try:
   with urllib.request.urlopen(urllib.request.Request(base+path,data=json.dumps(payload).encode(),headers=headers),timeout=30) as r:return json.load(r)
  except urllib.error.HTTPError as e:raise RuntimeError(str(e.code)+' '+e.read().decode())
 def fixture(**payload):return request('/workspace-tools-test',payload)
 def api(w,action='snapshot',**data):return request('/dsh-desktop/project-memory/v1',{'workspaceID':w['workspaceID'],'action':action,**data})['value']
 def mutate(w,**data):return api(w,'mutate',input=data)
 def fails(fn,phrase):
  try:fn()
  except RuntimeError as e:assert phrase in str(e),str(e)
  else:raise AssertionError('Invalid request accepted')
 process=start()
 try:
  first=fixture(action='create',path=str(project),title='阅读资料');second=fixture(action='create',path=str(other),title='另一个项目')
  a=api(first);assert a['profile']['entries']==[];assert a['config']['maxProfileEntries']==2,a['config']
  a=mutate(first,kind='profile',operation='add',text='文章面向初学者，表达简洁。',version=a['profile']['version'])
  read=fixture(action='invoke',sessionID=first['sessionID'],name='memory_profile',arguments={});assert not read['isError'];assert '初学者' in json.dumps(read,ensure_ascii=False)
  context=fixture(action='context',sessionID=first['sessionID']);assert '初学者' in json.dumps(context,ensure_ascii=False)
  assert api(second)['profile']['entries']==[]
  old=a['profile']['version'];a=mutate(first,kind='profile',operation='edit',index=0,text='文章面向专业读者。',version=old)
  fails(lambda:mutate(first,kind='profile',operation='edit',index=0,text='stale',version=old),'409')
  context=fixture(action='context',sessionID=first['sessionID']);assert '专业读者' in json.dumps(context,ensure_ascii=False);assert '初学者' not in json.dumps(context,ensure_ascii=False)
  fails(lambda:mutate(first,kind='profile',operation='add',text='过'*41,version=a['profile']['version']),'40')
  a=mutate(first,kind='profile',operation='add',text='保留引用来源。',version=a['profile']['version'])
  fails(lambda:mutate(first,kind='profile',operation='add',text='third',version=a['profile']['version']),'最多')
  a=mutate(first,kind='profile',operation='remove',index=1,version=a['profile']['version']);assert len(a['profile']['entries'])==1
  a=mutate(first,kind='fact',operation='add',text='测试项目采用按主题整理阅读资料。',category='convention',tags=['阅读'],version=a['emptyVersion']);fact=a['facts'][0]
  read=fixture(action='invoke',sessionID=first['sessionID'],name='memory_recall',arguments={'query':'阅读'});assert not read['isError'];assert fact['id'] in json.dumps(read)
  fails(lambda:mutate(second,kind='fact',operation='edit',id=fact['id'],version=fact['version'],text='跨项目',category='fact',tags=[]),'不属于')
  changed=fixture(action='invoke',sessionID=first['sessionID'],name='memory_edit',arguments={'id':fact['id'],'text':'Agent 更新后的记忆。'});assert not changed['isError'],changed
  fails(lambda:mutate(first,kind='fact',operation='edit',id=fact['id'],version=fact['version'],text='stale',category='fact',tags=[]),'409')
  a=api(first);fact=a['facts'][0];assert fact['text']=='Agent 更新后的记忆。'
  a=mutate(first,kind='fact',operation='archive',id=fact['id'],version=fact['version']);assert a['facts'][0]['state']=='archived'
  read=fixture(action='invoke',sessionID=first['sessionID'],name='memory_recall',arguments={});assert fact['id'] not in json.dumps(read)
  a=mutate(first,kind='fact',operation='restore',id=fact['id'],version=a['facts'][0]['version']);assert a['facts'][0]['state']=='active'
  from concurrent.futures import ThreadPoolExecutor
  v=a['profile']['version']
  def race(text):
   try:mutate(first,kind='profile',operation='edit',index=0,text=text,version=v);return 'saved'
   except RuntimeError as e:return 'conflict' if str(e).startswith('409') else str(e)
  with ThreadPoolExecutor(2) as pool:assert sorted(pool.map(race,['并发草稿甲','并发草稿乙']))==['conflict','saved']
  end=fixture(action='turn',sessionID=first['sessionID']);assert end[-1]['data']['reason']['kind']=='completed',end
  requests=fixture(action='requests');assert requests and all(r['provider']=='workspace-test' for r in requests),requests
  fails(lambda:request('/dsh-desktop/project-memory/v1',{'workspaceID':first['workspaceID'],'action':'snapshot'},False),'403')
  fails(lambda:request('/dsh-desktop/project-memory/v1',{'workspaceID':first['workspaceID'],'action':'snapshot'},True,True),'403')
  fails(lambda:api({'workspaceID':'unknown'}),'项目已移除')
  before=api(first);stop(process);process=start();reopened=fixture(action='create',path=str(project),title='重新打开');after=api(reopened)
  assert after['profile']==before['profile'] and after['facts']==before['facts']
  print('Memory integration passed: real plugin/domain, configured caps, project isolation, UI/agent bidirectional reads and writes, prompt refresh, optimistic conflicts, archive/restore, authentication and persistence. Only a local fixture model was used.')
 except BaseException:
  print((root/'runtime.log').read_text()[-6000:]);raise
 finally:stop(process)
PY
