import json
import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class KiwixConfigTests(unittest.TestCase):
    def test_registers_idempotently_and_preserves_other_servers(self):
        with tempfile.TemporaryDirectory() as d:
            home = pathlib.Path(d)
            bindir = home / '.local/bin'; bindir.mkdir(parents=True)
            agent = home / '.omp/agent'; agent.mkdir(parents=True)
            for name, script in {
                'uv': '#!/bin/sh\nexit 0\n',
                'omp': '#!/bin/sh\necho "$HOME/.omp/agent"\n',
                'git': '#!/bin/sh\nmkdir -p "$5/.git"\n',
            }.items():
                p = bindir / name; p.write_text(script); p.chmod(0o755)
            path = agent / 'mcp.json'
            path.write_text(json.dumps({'mcpServers': {'other': {'command': 'example'}}}))
            env = os.environ | {'HOME':d, 'PATH':str(bindir)+':'+os.environ['PATH']}
            for _ in range(2):
                r = subprocess.run(['bash',str(ROOT/'configure-kiwix.sh')],env=env,text=True,capture_output=True)
                self.assertEqual(r.returncode,0,r.stderr)
            data=json.loads(path.read_text())
            self.assertEqual(data['mcpServers']['other']['command'],'example')
            entry=data['mcpServers']['kiwix']
            self.assertEqual(entry['type'],'stdio')
            self.assertEqual(entry['env']['KIWIX_ARCHIVE_DIR'],str(home/'.local/share/kiwix-mcp/archives'))
            self.assertEqual(entry['args'],['run','--frozen','python','server.py'])
            data['mcpServers']['kiwix']['command']='custom'
            path.write_text(json.dumps(data))
            r=subprocess.run(['bash',str(ROOT/'configure-kiwix.sh')],env=env,text=True,capture_output=True)
            self.assertNotEqual(r.returncode,0)
            self.assertEqual(json.loads(path.read_text())['mcpServers']['kiwix']['command'],'custom')

if __name__ == '__main__': unittest.main()
