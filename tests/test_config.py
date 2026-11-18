import json, pathlib, subprocess, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]

def make_policy(data):
    return subprocess.run(['python3',str(ROOT/'firefox-policy.py')],input=json.dumps(data),text=True,capture_output=True)

class PolicyTests(unittest.TestCase):
 def test_preserves_unrelated_and_adds_requested(self):
    r=make_policy({'policies':{'DisableTelemetry':True}}); self.assertEqual(r.returncode,0,r.stderr)
    p=json.loads(r.stdout)['policies']; self.assertTrue(p['DisableTelemetry']); self.assertEqual(len(p['ExtensionSettings']),3)
    u=p['3rdparty']['Extensions']['uBlock0@raymondhill.net']; self.assertIn('twitch.tv##+js(twitch-videoad)',u['toOverwrite']['filters'])
    self.assertEqual(u['advancedSettings'][0][1],'https://raw.githubusercontent.com/pixeltris/TwitchAdSolutions/master/vaft/vaft-ublock-origin.js')
 def test_idempotent(self):
    a=make_policy({}); b=make_policy(json.loads(a.stdout)); self.assertEqual(json.loads(a.stdout),json.loads(b.stdout))
 def test_release_preserves_future_edits_and_is_idempotent(self):
    a=make_policy({})
    r=subprocess.run(['python3',str(ROOT/'firefox-policy.py'),'--release'],input=a.stdout,text=True,capture_output=True)
    self.assertEqual(r.returncode,0,r.stderr)
    released=json.loads(r.stdout); u=released['policies']['3rdparty']['Extensions']['uBlock0@raymondhill.net']
    self.assertNotIn('toOverwrite',u); self.assertIn('advancedSettings',u)
    self.assertEqual(json.loads(make_policy(released).stdout),released)
 def test_refuses_conflicting_managed_ubo(self):
    p={'policies':{'3rdparty':{'Extensions':{'uBlock0@raymondhill.net':{'someExistingSetting':True}}}}}
    self.assertNotEqual(make_policy(p).returncode,0)
 def test_shell_syntax(self):
    for script in ROOT.glob('*.sh'):
      with self.subTest(script=script.name): subprocess.run(['bash','-n',str(script)],check=True)
 def test_hdd_requires_arguments(self):
    r=subprocess.run(['bash',str(ROOT/'format-hdd.sh')],capture_output=True,text=True)
    self.assertNotEqual(r.returncode,0)
    self.assertIn('Usage:',r.stderr)
 def test_driver_selection_never_uses_open_meta(self):
    text=(ROOT/'install-system.sh').read_text(); self.assertIn('gsub(/-open$/, "", $i)',text)

class LocalModelConnectionTests(unittest.TestCase):
 def test_connect_preserves_existing_models_and_uses_loopback(self):
    import os, tempfile, threading, http.server, socketserver
    class Handler(http.server.BaseHTTPRequestHandler):
      def do_GET(self):
       self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b'{"data":[{"id":"example-local"}]}')
      def log_message(self,*args): pass
    class Server(socketserver.TCPServer): allow_reuse_address=True
    try: server=Server(('127.0.0.1',8000),Handler)
    except OSError as exc: self.skipTest(f'Cannot bind loopback in this sandbox: {exc}')
    thread=threading.Thread(target=server.serve_forever,daemon=True); thread.start()
    try:
     with tempfile.TemporaryDirectory() as td:
      home=pathlib.Path(td); (home/'.local/bin').mkdir(parents=True); (home/'.omp/agent').mkdir(parents=True)
      omp=home/'.local/bin/omp'; omp.write_text('''#!/bin/sh\nif [ "$1 $2" = "config path" ]; then echo "$HOME/.omp/agent"; elif [ "$1 $2" = "config list" ]; then echo '{"modelRoles":{"value":{"reviewer":"global/review"}}}'; elif [ "$1 $2" = "config get" ]; then echo '{"value":{}}'; elif [ "$1 $2" = "config set" ]; then printf '%s\\n' "$*" >> "$HOME/calls"; else exit 2; fi\n'''); omp.chmod(0o755)
      (home/'.omp/agent/models.yml').write_text('providers:\n  old-provider:\n    baseUrl: http://example.invalid\n')
      env=os.environ|{'HOME':td,'no_proxy':'127.0.0.1,localhost','NO_PROXY':'127.0.0.1,localhost'}
      r=subprocess.run(['bash',str(ROOT/'connect-colibri.sh'),'8000'],env=env,text=True,capture_output=True)
      self.assertEqual(r.returncode,0,r.stderr)
      content=(home/'.omp/agent/models.yml').read_text(); self.assertIn('old-provider',content); self.assertIn('http://127.0.0.1:8000/v1',content); self.assertIn('example-local',content)
      calls=(home/'calls').read_text(); self.assertIn('modelRoles',calls); self.assertNotIn('enabledModels',calls); self.assertIn('pc-setup-colibri/example-local',calls); self.assertIn('global/review',calls)
      import yaml
      config=home/'.omp/agent/models.yml'
      data=yaml.safe_load(config.read_text()); data['providers']['pc-setup-colibri']['models'][0]['maxTokens']=123
      config.write_text(yaml.safe_dump(data)); before=config.read_text()
      rerun=subprocess.run(['bash',str(ROOT/'connect-colibri.sh')],env=env,text=True,capture_output=True)
      self.assertNotEqual(rerun.returncode,0); self.assertEqual(config.read_text(),before)
    finally:
     server.shutdown(); server.server_close(); thread.join()

if __name__=='__main__': unittest.main()
