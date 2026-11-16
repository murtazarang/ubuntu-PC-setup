"""Windows power notifications for python.exe and pythonw.exe alike.

A hidden *top-level* window receives broadcasts; HWND_MESSAGE would not.
USB is serialized by DisplayState. Suspend/shutdown callbacks only attempt a
bounded backlight command, never sensor polling, rendering, closing or opening.
"""
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


class WindowsPowerListener:
    def __init__(self, state):
        self.state = state
        self.ready = threading.Event()
        self.error = None
        self.hwnd = None

    def __enter__(self):
        if os.name != 'nt':
            return self
        self.thread = threading.Thread(target=self._run, name='AX206 power events', daemon=True)
        self.thread.start()
        if not self.ready.wait(5):
            raise RuntimeError('Windows power listener did not start.')
        if self.error is not None:
            raise RuntimeError('Windows power listener failed.') from self.error
        return self

    def __exit__(self, *exc):
        if self.hwnd is not None:
            self.user32.PostMessageW(self.hwnd, 0x0010, 0, 0)  # WM_CLOSE
            self.thread.join(timeout=2)

    def _run(self):
        import ctypes
        from ctypes import wintypes as w
        user32 = ctypes.WinDLL('user32', use_last_error=True)
        kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
        self.user32 = user32
        result = ctypes.c_ssize_t
        callback_type = ctypes.WINFUNCTYPE(result, w.HWND, w.UINT, w.WPARAM, w.LPARAM)

        class WindowClass(ctypes.Structure):
            _fields_ = [('style', w.UINT), ('lpfnWndProc', callback_type),
                        ('cbClsExtra', ctypes.c_int), ('cbWndExtra', ctypes.c_int),
                        ('hInstance', w.HINSTANCE), ('hIcon', w.HICON),
                        ('hCursor', w.HANDLE), ('hbrBackground', w.HBRUSH),
                        ('lpszMenuName', w.LPCWSTR), ('lpszClassName', w.LPCWSTR)]

        kernel32.GetModuleHandleW.argtypes = [w.LPCWSTR]
        kernel32.GetModuleHandleW.restype = w.HMODULE
        user32.RegisterClassW.argtypes = [ctypes.POINTER(WindowClass)]
        user32.RegisterClassW.restype = w.ATOM
        user32.CreateWindowExW.argtypes = [w.DWORD, w.LPCWSTR, w.LPCWSTR, w.DWORD,
            ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int,
            w.HWND, w.HMENU, w.HINSTANCE, w.LPVOID]
        user32.CreateWindowExW.restype = w.HWND
        user32.DefWindowProcW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
        user32.DefWindowProcW.restype = result
        user32.GetMessageW.argtypes = [ctypes.POINTER(w.MSG), w.HWND, w.UINT, w.UINT]
        user32.GetMessageW.restype = w.BOOL
        user32.TranslateMessage.argtypes = [ctypes.POINTER(w.MSG)]
        user32.DispatchMessageW.argtypes = [ctypes.POINTER(w.MSG)]
        user32.DispatchMessageW.restype = result
        user32.PostMessageW.argtypes = [w.HWND, w.UINT, w.WPARAM, w.LPARAM]
        user32.DestroyWindow.argtypes = [w.HWND]
        user32.UnregisterClassW.argtypes = [w.LPCWSTR, w.HINSTANCE]
        user32.PostQuitMessage.argtypes = [ctypes.c_int]

        @callback_type
        def wndproc(hwnd, message, wp, lp):
            try:
                if message == 0x0218:  # WM_POWERBROADCAST
                    if wp == 4:  # PBT_APMSUSPEND
                        self.state.darken()
                    elif wp in (7, 18):  # RESUMESUSPEND / RESUMEAUTOMATIC
                        self.state.resume()
                    return 1
                if message == 0x0011:  # WM_QUERYENDSESSION, do not veto shutdown
                    return 1
                if message == 0x0016:  # WM_ENDSESSION, query may have been canceled
                    if wp:
                        self.state.darken(shutdown=True)
                    return 0
                if message == 0x0010:
                    user32.DestroyWindow(hwnd)
                    return 0
                if message == 0x0002:
                    user32.PostQuitMessage(0)
                    return 0
            except Exception:
                logging.exception('Windows power notification handler failed.')
            return user32.DefWindowProcW(hwnd, message, wp, lp)

        instance = kernel32.GetModuleHandleW(None)
        name = 'AX206PowerWindow-' + str(os.getpid())
        cls = WindowClass(0, wndproc, 0, 0, instance, None, None, None, None, name)
        registered = False
        try:
            if not user32.RegisterClassW(ctypes.byref(cls)):
                raise ctypes.WinError(ctypes.get_last_error())
            registered = True
            # No WS_VISIBLE and NULL parent: hidden top-level, NOT message-only.
            self.hwnd = user32.CreateWindowExW(0, name, name, 0, 0, 0, 0, 0,
                                              None, None, instance, None)
            if not self.hwnd:
                raise ctypes.WinError(ctypes.get_last_error())
            self.ready.set()
            msg = w.MSG()
            while True:
                status = user32.GetMessageW(ctypes.byref(msg), None, 0, 0)
                if status == -1:
                    raise ctypes.WinError(ctypes.get_last_error())
                if status == 0:
                    break
                user32.TranslateMessage(ctypes.byref(msg))
                user32.DispatchMessageW(ctypes.byref(msg))
        except Exception as exc:
            self.error = exc
            self.state.stopped.set()
            self.state.changed.set()
            logging.exception('Windows power listener stopped unexpectedly.')
        finally:
            self.ready.set()
            if self.hwnd:
                user32.DestroyWindow(self.hwnd)
                self.hwnd = None
            if registered:
                user32.UnregisterClassW(name, instance)


class SingleInstance:
    """One display process per interactive session, manual or scheduled."""
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
            self.handle = self.kernel.CreateMutexW(None, False, 'Local\\AX206Panel-1908-0102')
            if not self.handle:
                raise ctypes.WinError(ctypes.get_last_error())
            if ctypes.get_last_error() == 183:  # ERROR_ALREADY_EXISTS
                self.kernel.CloseHandle(self.handle)
                self.handle = None
                raise RuntimeError('An AX206 panel is already running in this Windows session.')
        return self

    def __exit__(self, *exc):
        if self.handle:
            self.kernel.CloseHandle(self.handle)
