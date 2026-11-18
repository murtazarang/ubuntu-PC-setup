"""SCM host for AX206Panel; installed by the machine-wide service installer.

This executable entry point must run from an administrator-owned installation,
not a user-writable LocalAppData directory. No interactive desktop is required.
"""
import json
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path

from lifecycle import DisplayState


class ServiceLifecycle:
    """Pure control mapping, also exercised by tests without installing a service."""
    def __init__(self, state):
        self.state = state

    def stop(self):
        self.state.darken(shutdown=True)

    def power(self, event):
        if event == 4:  # PBT_APMSUSPEND
            self.state.darken()
        elif event in (7, 18):  # PBT_APMRESUMESUSPEND / RESUMEAUTOMATIC
            self.state.resume()
        return 0  # NO_ERROR from HandlerEx


def service_backend():
    """Never search per-user/vcpkg/Chocolatey DLL locations as LocalSystem."""
    import ctypes
    from ctypes import wintypes
    import importlib
    get_dir = ctypes.windll.kernel32.GetSystemDirectoryW
    get_dir.argtypes = [wintypes.LPWSTR, wintypes.UINT]
    get_dir.restype = wintypes.UINT
    buffer = ctypes.create_unicode_buffer(32768)
    length = get_dir(buffer, len(buffer))
    if not length or length >= len(buffer):
        raise RuntimeError('Cannot resolve the protected Windows system directory')
    system = Path(buffer.value)
    for module, name in [('libusb0','libusb0.dll'), ('libusb1','libusb-1.0.dll')]:
        dll = system / name
        if dll.is_file():
            backend = importlib.import_module('usb.backend.' + module).get_backend(find_library=lambda _: str(dll))
            if backend is not None:
                return backend, module
    raise RuntimeError('No usable libusb0.dll or libusb-1.0.dll in Windows System32. '
                       'Service does not load USB libraries from user-writable folders. '
                       'The existing USB driver was not changed.')


def make_service(service_module, framework):
    class AX206Service(framework):
        _svc_name_ = 'AX206Panel'
        _svc_display_name_ = 'AX206 Display Panel'
        _svc_description_ = 'Portrait AX206 hardware monitor managed by ubuntu-PC-setup.'

        def __init__(self, args):
            super().__init__(args)
            self.state = DisplayState()
            self.lifecycle = ServiceLifecycle(self.state)

        def GetAcceptedControls(self):
            return super().GetAcceptedControls() | service_module.SERVICE_ACCEPT_POWEREVENT

        def SvcStop(self):
            self.ReportServiceStatus(service_module.SERVICE_STOP_PENDING)
            self.lifecycle.stop()

        def SvcShutdown(self):
            self.SvcStop()

        def SvcOtherEx(self, control, event_type, data):
            if control == service_module.SERVICE_CONTROL_POWEREVENT:
                return self.lifecycle.power(event_type)
            return super().SvcOtherEx(control, event_type, data)

        def SvcDoRun(self):
            from panel import main
            base = Path(__file__).resolve().parent
            from safe_theme import validate_theme
            validate_theme(base / 'portrait.yaml')
            # Config/log paths are fixed at installation, never from an account's
            # current working directory or interactive user's environment.
            config = json.loads((base / 'service.json').read_text(encoding='utf-8-sig'))
            rotation = config['rotation']
            if type(rotation) is not int or rotation not in (0, 90, 180, 270):
                raise ValueError('Invalid service rotation')
            log_dir = Path(config['log_dir'])
            if not log_dir.is_absolute():
                raise ValueError('Service log directory must be absolute')
            handler = RotatingFileHandler(log_dir / 'service.log', maxBytes=2_000_000,
                                          backupCount=2, encoding='utf-8')
            logging.basicConfig(level=logging.INFO, handlers=[handler], force=True)
            logging.info('AX206 Windows service starting')
            try:
                main(['--rotation', str(rotation)], state=self.state, backend_provider=service_backend)
                if not self.state.stopped.is_set():
                    raise RuntimeError('Panel loop exited without a stop request')
            except Exception:
                logging.exception('AX206 Windows service failed')
                raise  # SCM host reports failure; configured recovery restarts it.
            finally:
                handler.flush()
                handler.close()
    return AX206Service


def dispatch():
    import servicemanager
    import win32service
    import win32serviceutil
    import os
    base = Path(__file__).resolve().parent
    os.chdir(base)
    os.environ['AX206_LHM_DLL'] = str(base / 'source' / 'lib' / 'LibreHardwareMonitorLib.dll')
    service = make_service(win32service, win32serviceutil.ServiceFramework)
    servicemanager.Initialize()
    servicemanager.PrepareToHostSingle(service)
    servicemanager.StartServiceCtrlDispatcher()


if __name__ == '__main__':
    dispatch()
