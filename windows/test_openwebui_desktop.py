import importlib.util
from pathlib import Path
import subprocess
import sys
import unittest
import time
spec=importlib.util.spec_from_file_location('desktop', Path(__file__).with_name('openwebui_desktop.py'))
desktop=importlib.util.module_from_spec(spec);spec.loader.exec_module(desktop)

class OwnershipTests(unittest.TestCase):
    def setUp(self):
        self.child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(120)'])
        time.sleep(0.05)  # let the disposable child finish exec before recording its command
        p=desktop.psutil.Process(self.child.pid)
        self.record={'pid':p.pid,'created':p.create_time(),'command':p.cmdline()}
    def tearDown(self):
        if self.child.poll() is None:self.child.terminate()
        self.child.wait()
    def test_empty_record(self):self.assertIsNone(desktop.owned_process({}))
    def test_correct_identity(self):self.assertEqual(desktop.owned_process(self.record).pid,self.child.pid)
    def test_reused_pid_guard(self):
        wrong=dict(self.record,created=self.record['created']-10)
        desktop.stop_record(wrong)
        self.assertIsNone(self.child.poll())
    def test_changed_command_guard(self):
        wrong=dict(self.record,command=['unrelated.exe'])
        desktop.stop_record(wrong)
        self.assertIsNone(self.child.poll())
    def test_stop_only_recorded(self):
        desktop.stop_record(self.record)
        self.child.wait(timeout=3)
        self.assertIsNotNone(self.child.returncode)
class EnvironmentTests(unittest.TestCase):
    def test_inherited_cpu_and_auth_flags_do_not_override_managed_gpu(self):
        env=desktop.webui_environment({'hardware':'NvidiaSingle'}, {'USE_SLIM_DOCKER':'true','USE_CUDA_DOCKER':'false','WEBUI_AUTH':'false','OTHER':'keep','SENTENCE_TRANSFORMERS_BACKEND':'openvino','SENTENCE_TRANSFORMERS_MODEL_KWARGS':'{"device":"CPU"}'})
        self.assertEqual(env['USE_SLIM_DOCKER'],'false')
        self.assertEqual(env['USE_CUDA_DOCKER'],'true')
        self.assertEqual(env['WEBUI_AUTH'],'true')
        self.assertEqual(env['OTHER'],'keep')
        self.assertEqual(env['SENTENCE_TRANSFORMERS_BACKEND'],'torch')
        self.assertEqual(env['SENTENCE_TRANSFORMERS_MODEL_KWARGS'],'{}')
    def test_intel_explicit_openvino_kwargs_are_preserved(self):
        prefs={'SENTENCE_TRANSFORMERS_BACKEND':'openvino','SENTENCE_TRANSFORMERS_MODEL_KWARGS':'{"device":"GPU.1"}','USE_CUDA_DOCKER':'false','USE_SLIM_DOCKER':'false'}
        env=desktop.webui_environment({'hardware':'Intel','webui_environment':prefs},{})
        for key,value in prefs.items(): self.assertEqual(env[key],value)
    def test_explicit_conflicting_settings_preserved(self):
        for key,value in [('USE_SLIM_DOCKER','true'),('USE_CUDA_DOCKER','false'),('WEBUI_AUTH','false'),('SENTENCE_TRANSFORMERS_BACKEND','openvino'),('SENTENCE_TRANSFORMERS_MODEL_KWARGS','{"device":"cpu"}')]:
            config={'hardware':'NvidiaDual','webui_environment':{key:value}}
            with self.assertRaises(RuntimeError):desktop.webui_environment(config,{})
            self.assertEqual(config['webui_environment'][key],value)
if __name__=='__main__':unittest.main()
