import sys
import threading
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from lifecycle import DisplayState, SingleInstance


class Device:
    def __init__(self):
        self.off = 0

    def power_off(self):
        self.off += 1


class StateTests(unittest.TestCase):
    def test_suspend_resume_and_shutdown(self):
        state = DisplayState()
        state.device = Device()
        state.darken()
        self.assertTrue(state.paused.is_set())
        self.assertEqual(state.device.off, 1)
        state.resume()
        self.assertFalse(state.paused.is_set())
        self.assertTrue(state.reopen.is_set())
        state.darken(shutdown=True)
        state.resume()
        self.assertTrue(state.stopped.is_set())
        self.assertTrue(state.paused.is_set())

    def test_off_failure_does_not_cancel_shutdown(self):
        class Broken:
            def power_off(self):
                raise RuntimeError('USB unavailable')
        state = DisplayState()
        state.device = Broken()
        with self.assertLogs(level='ERROR'):
            state.darken(shutdown=True)
        self.assertTrue(state.stopped.is_set())
        self.assertTrue(state.lock.acquire(False))
        state.lock.release()

    def test_suspend_serializes_with_current_transaction(self):
        state = DisplayState()
        state.device = Device()
        state.lock.acquire()
        worker = threading.Thread(target=state.darken)
        worker.start()
        self.assertTrue(state.changed.wait(1))
        self.assertTrue(state.paused.is_set())
        self.assertEqual(state.device.off, 0)
        state.lock.release()
        worker.join(2)
        self.assertFalse(worker.is_alive())
        self.assertEqual(state.device.off, 1)

    def test_lock_busy_does_not_block_indefinitely(self):
        import time
        state = DisplayState()
        state.device = Device()
        state.lock.acquire()
        start = time.monotonic()
        try:
            with self.assertLogs(level='WARNING'):
                state.darken()
        finally:
            state.lock.release()
        self.assertLess(time.monotonic() - start, 1.8)
        self.assertEqual(state.device.off, 0)
        self.assertTrue(state.paused.is_set())


@unittest.skipUnless(sys.platform == 'win32', 'Windows message pump test')
class WindowsTests(unittest.TestCase):
    def test_duplicate_instance(self):
        with SingleInstance():
            with self.assertRaises(RuntimeError):
                with SingleInstance():
                    pass
        with SingleInstance():
            pass


if __name__ == '__main__':
    unittest.main()
