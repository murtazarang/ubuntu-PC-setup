import sys
from pathlib import Path
import unittest
from types import SimpleNamespace as NS
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from panel import orient, ambiguous_gpu, cleanup
from PIL import Image

class PortraitTests(unittest.TestCase):
    def test_clockwise_and_counterclockwise(self):
        image = Image.new('RGB', (320,480)); image.putpixel((0,0),(255,0,0))
        self.assertEqual(orient(image,(480,320),90).getpixel((0,319)), (255,0,0))
        self.assertEqual(orient(image,(480,320),270).getpixel((479,0)), (255,0,0))
    def test_native_portrait(self):
        self.assertEqual(orient(Image.new('RGB',(320,480)),(320,480),0).size,(320,480))
    def test_wrong_resolution_rejected(self):
        with self.assertRaises(ValueError): orient(Image.new('RGB',(320,480)),(800,480),90)
    def test_gpu_ambiguity(self):
        def source(types): return [NS(name='lhm',_computer=NS(Hardware=[NS(HardwareType=t) for t in types]))]
        self.assertTrue(ambiguous_gpu(source(['Cpu','GpuNvidia','GpuNvidia'])))
        self.assertFalse(ambiguous_gpu(source(['Cpu','GpuNvidia','GpuAmd'])))
        self.assertFalse(ambiguous_gpu([]))

class CleanupTests(unittest.TestCase):
    def test_failure_does_not_skip_other_sources_or_backlight(self):
        calls = []
        def fail_close():
            calls.append('first')
            raise RuntimeError('sensor disconnected')
        def good_close(): calls.append('second')
        def fail_backlight(level):
            calls.append(('backlight',level))
            raise RuntimeError('USB disconnected')
        with self.assertLogs(level='WARNING') as logs:
            cleanup([NS(name='first',close=fail_close), NS(close=good_close)],
                    NS(set_backlight=fail_backlight))
        self.assertEqual(calls, ['first','second',('backlight',0)])
        self.assertEqual(len(logs.output),2)

    def test_original_error_survives_cleanup_failure(self):
        def fail_backlight(level): raise ValueError('cleanup failure')
        with self.assertLogs(level='WARNING'):
            with self.assertRaisesRegex(RuntimeError, 'original USB failure'):
                try:
                    raise RuntimeError('original USB failure')
                finally:
                    cleanup([], NS(set_backlight=fail_backlight))

if __name__ == '__main__': unittest.main()
