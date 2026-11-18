import unittest
import sys, types
from unittest.mock import patch
import openwebui_gpu as g

class Core:
    def __init__(self, devices): self.devices=devices; self.available_devices=list(devices)
    def get_property(self, device, prop):
        assert prop=='FULL_DEVICE_NAME'
        return self.devices[device]

class Tests(unittest.TestCase):
    def test_selects_discrete_not_igpu(self):
        c=Core({'CPU':'Intel','GPU.0':'Intel UHD Graphics 730','GPU.1':'Intel Arc B580 Graphics'})
        env=g.environment(c)
        self.assertEqual(g.verify(c,env),'GPU.1')
        self.assertIn('GPU.1',env[g.KWARGS[0]])
    def test_missing_or_multiple_gpu_refused(self):
        for devices in ({'CPU':'Intel'}, {'GPU':'Intel UHD Graphics'}, {'GPU.0':'Intel Arc B580','GPU.1':'Intel Arc B580'}):
            with self.assertRaisesRegex(RuntimeError,'exactly one'):g.environment(Core(devices))
    def test_changed_device_and_fallback_refused(self):
        c=Core({'GPU.1':'Intel Arc B580'}); env=g.environment(c)
        for bad in ('CPU','AUTO','HETERO:GPU.1,CPU','GPU.0'):
            changed=dict(env); changed[g.KWARGS[0]]='{"device":"'+bad+'"}'
            with self.assertRaises(RuntimeError):g.verify(c,changed)
        for key,value in ((g.BACKENDS[1],'torch'),('USE_SLIM_DOCKER','true'),('USE_CUDA_DOCKER','true'),(g.TRUST[0],'true')):
            changed=dict(env);changed[key]=value
            with self.assertRaises(RuntimeError):g.verify(c,changed)
    def test_malformed_configuration_refused(self):
        c=Core({'GPU':'Intel Arc B580'});env=g.environment(c)
        for value in ('', '[]', 'null', '{}'):
            changed=dict(env);changed[g.KWARGS[1]]=value
            with self.assertRaises(RuntimeError):g.verify(c,changed)

class ProbeTests(unittest.TestCase):
    def test_native_loader_arguments_and_device_readback(self):
        class Request:
            def get_property(self, prop):
                self.prop=prop;return ['GPU.1']
        class Model:
            def __init__(self):self.transformers_model=type('Native',(),{'request':Request()})()
            def encode(self, values):self.values=values
            def predict(self, values):self.values=values
        models=[];calls=[]
        def loader(*args):calls.append(args);m=Model();models.append(m);return m
        c=Core({'GPU.1':'Intel Arc B580'})
        self.assertEqual(g.probe(c,g.environment(c),'embed','rerank',(loader,loader)),'GPU.1')
        self.assertEqual(calls,[('','embed'),('','rerank')])
        self.assertTrue(all(m.values for m in models))
        self.assertTrue(all(m.transformers_model.request.prop=='EXECUTION_DEVICES' for m in models))
    def test_cpu_or_missing_compiled_model_refused(self):
        for actual in (['CPU'],['GPU.0'],['GPU.1','CPU'],[]):
            request=type('Request',(),{'get_property':lambda self,p:actual})()
            model=type('Model',(),{'transformers_model':type('Native',(),{'request':request})()})()
            with self.assertRaises(RuntimeError):g.assert_execution(model,'GPU.1')
        with self.assertRaises(RuntimeError):g.assert_execution(object(),'GPU.1')
    def test_webui_swallowed_load_failure_is_error(self):
        c=Core({'GPU.1':'Intel Arc B580'})
        with self.assertRaisesRegex(RuntimeError,'failed to load'):
            g.probe(c,g.environment(c),'embed','rerank',(lambda *args:None,None))

class CudaTests(unittest.TestCase):
    def modules(self, cuda=True, device='cuda', output_cuda=True):
        target_device=device
        class Model:
            device=types.SimpleNamespace(type=target_device)
            def encode(self, values, convert_to_tensor):
                assert convert_to_tensor is True
                return types.SimpleNamespace(is_cuda=output_cuda)
            predict=encode
        return {'torch':types.SimpleNamespace(cuda=types.SimpleNamespace(is_available=lambda:cuda)),
                'open_webui':types.ModuleType('open_webui'),
                'open_webui.env':types.SimpleNamespace(DEVICE_TYPE=device,USE_SLIM=False),
                'open_webui.routers':types.ModuleType('open_webui.routers'),
                'open_webui.routers.retrieval':types.SimpleNamespace(get_ef=lambda *a:Model(),get_rf=lambda *a:Model())}
    def test_cuda_probe_executes_both_native_models(self):
        with patch.dict(sys.modules,self.modules()):g.probe_cuda('embed','rank')
    def test_missing_cuda_and_cpu_outputs_refused(self):
        for kwargs in ({'cuda':False},{'device':'cpu'},{'output_cuda':False}):
            with patch.dict(sys.modules,self.modules(**kwargs)),self.assertRaises(RuntimeError):
                g.probe_cuda('embed','rank')

if __name__=='__main__':unittest.main()
