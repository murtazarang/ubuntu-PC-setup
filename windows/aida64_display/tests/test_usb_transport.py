"""No USB hardware or drivers are used; exercise exact command/deadline code."""
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


class TransportTests(unittest.TestCase):
    def setUp(self):
        protocol = types.ModuleType('ax206panel.device')
        protocol.AX206Device = type('Base', (), {})
        self.protocol = protocol
        protocol.DeviceError = protocol.ProtocolError = RuntimeError
        protocol.ENDPT_OUT, protocol.ENDPT_IN = 1, 129
        protocol.CSW_LEN, protocol.CSW_SIGNATURE = 13, b'USBS'
        protocol.PROPERTY_BRIGHTNESS = 1
        protocol.build_cbw = lambda cdb, size: b'x' * 31
        protocol.cdb_set_property = lambda p, v: bytes([p, v])
        package = types.ModuleType('ax206panel')
        package.device = protocol
        self.modules = patch.dict(sys.modules, {'ax206panel': package, 'ax206panel.device': protocol})
        self.modules.start()
        spec = importlib.util.spec_from_file_location('transport_under_test', Path(__file__).resolve().parents[1] / 'usb_transport.py')
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.obj = self.module.BoundedAX206Device()
        self.calls = []
        calls = self.calls
        class USB:
            def write(self, endpoint, data, timeout):
                calls.append(('write', timeout))
                return len(data)
            def read(self, endpoint, count, timeout):
                calls.append(('read', timeout))
                return b'USBS' + bytes(9)
        self.obj._dev = USB()

    def tearDown(self):
        self.modules.stop()

    def test_power_off_uses_remaining_deadline(self):
        with patch.object(self.module.time, 'monotonic', side_effect=[10, 10.1, 10.3]):
            self.obj.power_off()
        self.assertLessEqual(self.calls[0][1], 400)
        self.assertLessEqual(self.calls[1][1], 200)

    def test_expired_deadline_prevents_next_transfer(self):
        with patch.object(self.module.time, 'monotonic', side_effect=[10, 10.1, 11]):
            with self.assertRaises(RuntimeError):
                self.obj.power_off()
        self.assertEqual(len(self.calls), 1)

    def test_invalid_status_is_rejected_without_retries(self):
        self.obj._dev.read = lambda *args: b'BAD!' + bytes(9)
        with self.assertRaises(RuntimeError):
            self.obj.power_off()

    def test_short_command_write(self):
        self.obj._dev.write = lambda *args: 1
        with self.assertRaises(RuntimeError):
            self.obj.power_off()

    def test_nonzero_status(self):
        self.obj._dev.read = lambda *args: b'USBS' + bytes(8) + b'\x01'
        with self.assertRaises(RuntimeError):
            self.obj.power_off()

    def test_failed_open_releases_device(self):
        closed = []
        cls = self.module.BoundedAX206Device
        self.protocol.find_ax206 = lambda backend: [object()]
        cls.__init__ = lambda obj, usb: None
        cls._claim = lambda obj: None
        cls.close = lambda obj: closed.append(obj)
        def fail(obj):
            raise RuntimeError('parameter failure')
        cls._get_lcd_params = fail
        with self.assertRaises(RuntimeError):
            cls.open()
        self.assertEqual(len(closed), 1)


if __name__ == '__main__':
    unittest.main()
