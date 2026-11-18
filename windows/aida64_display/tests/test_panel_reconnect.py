import contextlib
import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import lifecycle


class ReconnectTests(unittest.TestCase):
    def test_transfer_failure_reopens_and_resume_reopens(self):
        self.run_scenario(False)

    def test_late_hardware_sensors_are_rediscovered(self):
        self.run_scenario(True)

    def run_scenario(self, late_sensors):
        from PIL import Image
        calls = []
        state = lifecycle.DisplayState()
        state.changed = Mock()
        devices = []

        class Device:
            width, height = 480, 320
            def __init__(self):
                self.number = len(devices)
                devices.append(self)
            @classmethod
            def open(cls, **kwargs):
                calls.append('open')
                return cls()
            def blit(self, image):
                calls.append(('blit', self.number))
                if self.number == 0:
                    raise RuntimeError('simulated disconnected USB')
            def set_backlight(self, level):
                calls.append(('light', self.number, level))
            def power_off(self):
                calls.append(('off', self.number))
            def close(self):
                calls.append(('close', self.number))

        polls = []
        def poll(sources):
            polls.append(1)
            if len(polls) == 3:
                state.darken()
                state.resume()
            if len(polls) == 4:
                state.stopped.set()
            if late_sensors and len(polls) == 1:
                return {}
            return {'cpu.temp': 40, 'gpu.temp': 40}

        def module(name, **attrs):
            value = types.ModuleType(name)
            value.__dict__.update(attrs)
            return value

        engine = Mock()
        engine.render.return_value = Image.new('RGB', (320, 480))
        source = Mock(name='source')
        reopen_sensors = Mock(return_value=[source])
        fake = {
            'ax206panel': module('ax206panel'),
            'ax206panel.render': module('ax206panel.render'),
            'ax206panel.render.engine': module('engine', RenderEngine=lambda theme: engine),
            'ax206panel.render.theme': module('theme', load_theme=lambda path: None),
            'ax206panel.device': module('device', get_backend=lambda name: (None, 'fake')),
            'ax206panel.framebuffer': module('framebuffer', image_to_rgb565=lambda image: b'pixels'),
            'ax206panel.sensors': module('sensors', open_sources=reopen_sensors, merge_polls=poll),
            'usb_transport': module('usb_transport', BoundedAX206Device=Device),
        }
        spec = importlib.util.spec_from_file_location('panel_under_test', Path(__file__).resolve().parents[1] / 'panel.py')
        panel = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(panel)
        with patch.dict(sys.modules, fake), patch.object(sys, 'argv', ['panel.py']), \
             patch.object(panel, 'DisplayState', return_value=state), \
             patch.object(panel, 'SingleInstance', side_effect=contextlib.nullcontext), \
             patch.object(panel.time, 'monotonic', side_effect=[0, 31, 32, 33, 34]):
            with self.assertLogs(level='ERROR'):
                panel.main()
        expected = 2 if late_sensors else 3
        self.assertEqual(len(devices), expected)
        self.assertIn(('close', 0), calls)
        self.assertIn(('blit', expected-1), calls)
        self.assertLess(calls.index(('blit', expected-1)), calls.index(('light', expected-1, 7)))
        self.assertEqual(calls[-1], ('close', expected-1))
        self.assertEqual(reopen_sensors.call_count, 2 if late_sensors else 1)
        self.assertEqual(source.close.call_count, 2 if late_sensors else 1)



if __name__ == '__main__':
    unittest.main()
