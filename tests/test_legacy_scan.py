import pathlib,unittest
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Scan(unittest.TestCase):
 def test_unreadable_walk_stops_cleanup(self):
  source=(ROOT/'remove-legacy-ai.sh').read_text().split('check_paths() {',1)[1].split("<<'PY'\n",1)[1].split('\nPY',1)[0]
  def failed_walk(path,followlinks,onerror):
   self.assertFalse(followlinks)
   onerror(PermissionError('fixture unreadable directory'))
   return []
  with patch('sys.argv',['scan',str(ROOT)]),patch('os.walk',side_effect=failed_walk):
   with self.assertRaisesRegex(SystemExit,'Cannot safely inspect old data'):exec(source,{'__name__':'__main__'})
if __name__=='__main__':unittest.main()
