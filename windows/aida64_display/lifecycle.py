import logging
import os
import threading


class DisplayState:
    def __init__(self):
        self.lock = threading.Lock()
        self.paused = threading.Event()
        self.stopped = threading.Event()
        self.reopen = threading.Event()
        self.changed = threading.Event()
        self.device = None

    def darken(self, shutdown=False):
        self.paused.set()  # prevent any later frame from relighting the panel
        if shutdown:
            self.stopped.set()
        self.changed.set()
        # Normal USB transactions have an 800ms total deadline. Leave time
        # within Windows' ~2-second suspend allowance for the off transaction.
        if not self.lock.acquire(timeout=0.9):
            logging.warning('Display busy; could not turn backlight off before power transition.')
            return
        try:
            if self.device is not None:
                try:
                    self.device.power_off()  # 500ms transport deadline
                except Exception:
                    logging.exception('Backlight-off command failed during power transition.')
        finally:
            self.lock.release()

    def resume(self):
        if not self.stopped.is_set():
            self.reopen.set()
            self.paused.clear()
            self.changed.set()


class SingleInstance:
    """One display process across service and interactive Windows sessions."""
    def __enter__(self):
        self.handle = None
        if os.name == 'nt':
            import ctypes
            from ctypes import wintypes as w
            self.kernel = ctypes.WinDLL('kernel32', use_last_error=True)
            self.kernel.CreateMutexW.argtypes = [w.LPVOID, w.BOOL, w.LPCWSTR]
            self.kernel.CreateMutexW.restype = w.HANDLE
            self.kernel.CloseHandle.argtypes = [w.HANDLE]
            ctypes.set_last_error(0)
            self.handle = self.kernel.CreateMutexW(None, False, 'Global\\AX206Panel-1908-0102')
            if not self.handle:
                raise ctypes.WinError(ctypes.get_last_error())
            if ctypes.get_last_error() == 183:  # ERROR_ALREADY_EXISTS
                self.kernel.CloseHandle(self.handle)
                self.handle = None
                raise RuntimeError('An AX206 panel is already running on this computer.')
        return self

    def __exit__(self, *exc):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
