#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json,os,shutil,socket,subprocess,tempfile,time,urllib.request,urllib.error,uuid
from pathlib import Path
runtime=shutil.which('dsh')
if not runtime:raise SystemExit('Install DSH for the optional runtime integration test.')
repo=Path.cwd()
with tempfile.TemporaryDirectory(prefix='dsh-workspace-integration-') as temporary:
 root=Path(temporary);home=root/'dsh';home.mkdir();project=root/'project';project.mkdir();other=root/'other';other.mkdir();token=uuid.uuid4().hex+uuid.uuid4().hex
 with socket.socket() as s:s.bind(('127.0.0.1',0));port=s.getsockname()[1]
 patch=root/'test.yml';patch.write_text(json.dumps([{'insert':[
  {'id':'workspace-tools','name':str(repo/'Resources/WorkspaceTools/host.mjs'),'config':{'storagePath':str(home/'desktop/workspace-tools.json'),'token':token}},
  {'id':'workspace-test','name':str(repo/'Tests/WorkspaceTools/runtime-fixture.mjs'),'config':{'token':token}}
 ]}]))
 log=(root/'runtime.log').open('wb');process=subprocess.Popen([runtime,'web','--patch',str(patch),'--host','127.0.0.1','--port',str(port),'--no-open'],cwd=root,env=dict(os.environ,DSH_HOME=str(home),DSH_TELEMETRY_DISABLED='1'),stdout=log,stderr=log)
 base=f'http://127.0.0.1:{port}'
 def request(path,payload,auth=True):
  headers={'Content-Type':'application/json'}
  if auth:headers['Authorization']='Bearer '+token
  req=urllib.request.Request(base+path,data=json.dumps(payload).encode(),headers=headers)
  try:
   with urllib.request.urlopen(req,timeout=30) as r:return json.load(r)
  except urllib.error.HTTPError as e:raise RuntimeError(str(e.code)+' '+e.read().decode())
 def fixture(**payload):return request('/workspace-tools-test',payload)
 def api(workspace,**payload):return request('/dsh-desktop/workspace-tools/v1',dict(workspace,**payload))['value']
 try:
  for _ in range(150):
   if process.poll() is not None:raise RuntimeError('DSH exited: '+(root/'runtime.log').read_text()[-4000:])
   try:
    with urllib.request.urlopen(base+'/dsh-desktop/workspace-tools.js',timeout=1) as r:
     if r.status==200:break
   except OSError:time.sleep(.2)
  else:raise RuntimeError('Startup timeout: '+(root/'runtime.log').read_text()[-6000:])
  first=fixture(action='create',path=str(project),title='阅读资料');second=fixture(action='create',path=str(other),title='其他项目')
  note=api(first,action='mutate',kind='notes',operation='add',input={'title':'用户便签','body':'项目背景：阅读历史文献。','pinned':True})
  result=fixture(action='invoke',sessionID=first['sessionID'],name='workspace_todo_add',arguments={'title':'Agent 添加的待办'})
  assert result['isError'] is False,result
  state=api(first,action='snapshot');assert state['todos'][0]['title']=='Agent 添加的待办'
  assert api(second,action='snapshot')['todos']==[]
  context=fixture(action='context',sessionID=first['sessionID']);assert '用户便签' in json.dumps(context,ensure_ascii=False);assert any(t['name']=='workspace_note_read' for t in context['tools'])
  old=state['todos'][0];api(first,action='mutate',kind='todos',operation='update',input={'id':old['id'],'revision':old['revision'],'status':'completed'})
  try:api(first,action='mutate',kind='todos',operation='update',input={'id':old['id'],'revision':old['revision'],'title':'stale'})
  except RuntimeError as e:assert '修改' in str(e)
  else:raise AssertionError('Stale update was accepted')
  end=fixture(action='turn',sessionID=first['sessionID']);assert end[-1]['data']['reason']['kind']=='completed',end
  schedule=api(first,action='mutate',kind='schedules',operation='add',input={'title':'定时测试','prompt':'参考便签完成测试。','frequency':'once','execution':'agent','at':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(time.time()+120)),'timezone':'Asia/Shanghai'})
  run=api(first,action='run',id=schedule['id'])
  for _ in range(100):
   state=api(first,action='snapshot');record=next(r for r in state['runs'] if r['id']==run['id'])
   if record['status']!='running':break
   time.sleep(.1)
  assert record['status']=='completed',record
  assert record['sessionID'].startswith('desktop-scheduled-')
  completed_context=fixture(action='context',sessionID=record['sessionID']);assert '用户便签' in json.dumps(completed_context,ensure_ascii=False), 'Completed scheduled conversation was disposed and became unavailable in live history'
  requests=fixture(action='requests');assert any('用户便签' in json.dumps(r,ensure_ascii=False) for r in requests);assert all(r['provider']=='workspace-test' for r in requests),requests
  try:request('/dsh-desktop/workspace-tools/v1',dict(first,action='snapshot'),False)
  except RuntimeError as e:assert str(e).startswith('403')
  else:raise AssertionError('Unauthenticated request succeeded')
  print('Real DSH integration passed: agent tools, workspace isolation, UI mutations, live prompt context, conflicts, native authentication, model turn and scheduled AI conversation. Only a local fixture model was used.')
 except BaseException:
  print((root/'runtime.log').read_text()[-6000:]);raise
 finally:
  process.terminate()
  try:process.wait(timeout=10)
  except subprocess.TimeoutExpired:process.kill();process.wait()
PY
