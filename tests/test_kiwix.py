import os,pathlib,subprocess,tempfile,unittest,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
class KiwixConfigTests(unittest.TestCase):
 def test_compatibility_entry_forwards_without_touching_old_configuration(self):
  with tempfile.TemporaryDirectory() as d:
   home=pathlib.Path(d);src=home/'src';src.mkdir();old=home/'.omp/agent';old.mkdir(parents=True)
   config=old/'mcp.json';config.write_text('{"mcpServers":{"custom":{"command":"keep"}}}')
   archive=home/'.local/share/kiwix-mcp/archives';archive.mkdir(parents=True);(archive/'saved.zim.part').write_bytes(b'partial')
   shutil.copy(ROOT/'configure-kiwix.sh',src)
   target=src/'configure-openwebui.sh';target.write_text('#!/bin/sh\nprintf ran >> "$HOME/calls"\n');target.chmod(0o755)
   for _ in range(2):
    r=subprocess.run(['bash',str(src/'configure-kiwix.sh')],env=os.environ|{'HOME':d},capture_output=True,text=True)
    self.assertEqual(r.returncode,0,r.stderr)
   self.assertEqual((home/'calls').read_text(),'ranran')
   self.assertEqual(config.read_text(),'{"mcpServers":{"custom":{"command":"keep"}}}')
   self.assertEqual((archive/'saved.zim.part').read_bytes(),b'partial')
if __name__=='__main__':unittest.main()
