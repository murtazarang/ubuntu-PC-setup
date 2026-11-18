import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from service_host import ServiceLifecycle, make_service
from lifecycle import DisplayState


class ServiceTests(unittest.TestCase):
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
