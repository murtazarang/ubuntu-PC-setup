"""Pinned AX206 protocol with per-command deadlines, no global monkeypatches."""
import time
from ax206panel import device as protocol


class BoundedAX206Device(protocol.AX206Device):
    def _wrap_scsi(self, cdb, data_out=None, read_len=0, *, budget=0.8):
        deadline = time.monotonic() + budget

        def timeout():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise protocol.DeviceError('AX206 command deadline expired')
            return max(1, int(remaining * 1000))

        if self._dev is None:
            raise protocol.DeviceError('device is closed')
        data_len = len(data_out) if data_out is not None else read_len
        cbw = protocol.build_cbw(cdb, data_len)
        if self._dev.write(protocol.ENDPT_OUT, cbw, timeout()) != len(cbw):
            raise protocol.ProtocolError('short command write')
        result = None
        if data_out is not None:
            if self._dev.write(protocol.ENDPT_OUT, data_out, timeout()) != len(data_out):
                raise protocol.ProtocolError('short pixel write')
        elif read_len:
            result = bytes(self._dev.read(protocol.ENDPT_IN, read_len, timeout()))
            if len(result) != read_len:
                raise protocol.ProtocolError('short parameter read')
        csw = bytes(self._dev.read(protocol.ENDPT_IN, protocol.CSW_LEN, timeout()))
        if len(csw) != protocol.CSW_LEN or not csw.startswith(protocol.CSW_SIGNATURE) or csw[12]:
            raise protocol.ProtocolError('invalid AX206 command status')
        return result

    def power_off(self):
        self._wrap_scsi(protocol.cdb_set_property(protocol.PROPERTY_BRIGHTNESS, 0), budget=0.5)

    @classmethod
    def open(cls, index=0, backend=None):
        devices = protocol.find_ax206(backend)
        if not 0 <= index < len(devices):
            raise protocol.DeviceNotFoundError('AX206 display is not connected or not available.')
        obj = cls(devices[index])
        try:
            obj._claim()
            obj.width, obj.height = obj._get_lcd_params()
            return obj
        except Exception:
            obj.close()
            raise
