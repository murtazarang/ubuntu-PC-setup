import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from service_host import ServiceLifecycle, make_service, load_system_backend
from lifecycle import DisplayState


class ServiceTests(unittest.TestCase):
    def test_backend_uses_only_explicit_system_dll_and_falls_back(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'libusb0.dll').touch()
            (root / 'libusb-1.0.dll').touch()
            seen = []
            def loader(module):
                def get_backend(find_library):
                    seen.append((module, find_library('ignored')))
                    if module.endswith('libusb0'):
                        raise OSError('wrong DLL architecture')
                    return 'mock-backend'
                return SimpleNamespace(get_backend=get_backend)
            with self.assertLogs(level='ERROR'):
                result = load_system_backend(root, loader)
            self.assertEqual(result, ('mock-backend','libusb1'))
            self.assertEqual(seen, [('usb.backend.libusb0', str(root/'libusb0.dll')),
                                    ('usb.backend.libusb1', str(root/'libusb-1.0.dll'))])

    def test_no_user_directory_backend_fallback(self):
        with tempfile.TemporaryDirectory() as folder:
            def loader(module):
                self.fail('Must not search a backend without a protected DLL')
            with self.assertRaises(RuntimeError):
                load_system_backend(Path(folder), loader)

    def test_suspend_resume_stop(self):
        state = DisplayState()
        life = ServiceLifecycle(state)
        self.assertEqual(life.power(4), 0)
        self.assertTrue(state.paused.is_set())
        life.power(18)
        self.assertFalse(state.paused.is_set())
        self.assertTrue(state.reopen.is_set())
        life.stop()
        life.power(7)
        self.assertTrue(state.stopped.is_set())
        self.assertTrue(state.paused.is_set())

    def test_unrelated_power_event_does_not_pause(self):
        state = DisplayState()
        ServiceLifecycle(state).power(10)
        self.assertFalse(state.paused.is_set())

    def test_service_callbacks_and_controls(self):
        api = SimpleNamespace(SERVICE_ACCEPT_POWEREVENT=64,
                              SERVICE_CONTROL_POWEREVENT=13,
                              SERVICE_STOP_PENDING=3)
        class Framework:
            def __init__(self, args): pass
            def GetAcceptedControls(self): return 5
            def ReportServiceStatus(self, status): self.status = status
            def SvcOtherEx(self, *args): return 120
        service = make_service(api, Framework)([])
        self.assertEqual(service.GetAcceptedControls(), 69)
        service.SvcOtherEx(13, 4, None)
        self.assertTrue(service.state.paused.is_set())
        service.SvcOtherEx(13, 18, None)
        self.assertFalse(service.state.paused.is_set())
        self.assertEqual(service.SvcOtherEx(999, 0, None), 120)
        service.SvcShutdown()
        self.assertEqual(service.status, 3)
        self.assertTrue(service.state.stopped.is_set())

if __name__ == '__main__':
    unittest.main()
