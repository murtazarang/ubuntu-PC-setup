"""Small portrait runner using the pinned win-ax206-display public modules."""
import argparse
import logging
from pathlib import Path
import time
from lifecycle import DisplayState, SingleInstance
from PIL import Image


def orient(image, physical_size, rotation):
    """Rotate without scaling; reject dimensions rather than distort text."""
    operations = {90: Image.Transpose.ROTATE_90,
                  180: Image.Transpose.ROTATE_180,
                  270: Image.Transpose.ROTATE_270}
    output = image if rotation == 0 else image.transpose(operations[rotation])
    if output.size != physical_size:
        raise ValueError(f"Theme after rotation is {output.size}, panel reports {physical_size}. "
                         "Choose 90/270 for a 480x320 panel or 0/180 for 320x480; "
                         "other sizes need their own theme. Nothing was sent.")
    return output


def ambiguous_gpu(sources):
    """Pinned upstream collapses GPUs of one vendor into a shared key."""
    for source in sources:
        if getattr(source, 'name', '') == 'lhm':
            types = [str(h.HardwareType) for h in source._computer.Hardware
                     if str(h.HardwareType).startswith('Gpu')]
            if len(types) != len(set(types)):
                return True
    return False


def cleanup(sources, device):
    """Attempt every cleanup operation without hiding the original failure."""
    for source in sources:
        try:
            source.close()
        except Exception as exc:
            logging.warning('Could not close sensor source %s: %s',
                            getattr(source, 'name', 'unknown'), exc)
    try:
        device.set_backlight(0)
    except Exception as exc:
        logging.warning('Could not turn off display backlight: %s', exc)


def main(argv=None, state=None, backend_provider=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('--rotation', type=int, choices=[0,90,180,270], default=270,
                        help='Counterclockwise rotation of portrait image into physical framebuffer')
    parser.add_argument('--index', type=int, default=0)
    parser.add_argument('--preview', type=Path)
    args = parser.parse_args(argv)
    from ax206panel.render.engine import RenderEngine
    from ax206panel.render.theme import load_theme
    engine = RenderEngine(load_theme(str(Path(__file__).with_name('portrait.yaml'))))
    if args.preview:
        engine.render({'cpu.temp':62, 'cpu.load':38, 'gpu.temp':67,
                       'gpu.load':81, 'ram.percent':54}).save(args.preview)
        print(f'Synthetic preview (not measured temperatures): {args.preview}')
        return
    from ax206panel.device import get_backend
    from usb_transport import BoundedAX206Device
    from ax206panel.framebuffer import image_to_rgb565
    from ax206panel.sensors import open_sources, merge_polls
    logging.basicConfig(level=logging.INFO)
    backend, backend_name = backend_provider() if backend_provider else get_backend('auto')
    state = state if state is not None else DisplayState()
    sources = []
    device = None
    warned = False
    sensor_retry_at = 0.0
    with SingleInstance():
        try:
            sources = open_sources()
            sensor_retry_at = time.monotonic() + 30
            hide_gpu = ambiguous_gpu(sources)
            if hide_gpu:
                logging.warning('Multiple GPUs of the same vendor: hiding ambiguous GPU readings.')
            while not state.stopped.is_set():
                if state.paused.is_set():
                    state.changed.wait(1)
                    state.changed.clear()
                    continue
                # Sensors and image rendering run outside the USB lock so a slow
                # sensor never prevents the listener sending the off command.
                values = merge_polls(sources)
                if ('cpu.temp' not in values or 'gpu.temp' not in values) and time.monotonic() >= sensor_retry_at:
                    sensor_retry_at = time.monotonic() + 30
                    logging.info('Retrying hardware sensor discovery after missing temperature readings.')
                    for source in sources:
                        try:
                            source.close()
                        except Exception:
                            logging.exception('Could not close sensor before retry.')
                    sources = open_sources()
                    hide_gpu = ambiguous_gpu(sources)
                    values = merge_polls(sources)
                if hide_gpu:
                    values = {k:v for k,v in values.items() if not k.startswith('gpu.')}
                if not warned and ('cpu.temp' not in values or 'gpu.temp' not in values):
                    logging.warning('Temperature unavailable. Missing values are shown as --.')
                    warned = True
                rendered = engine.render(values)
                # Opening/closing may involve driver calls not bounded by PyUSB
                # transfer timeouts. Do them OUTSIDE the power-notification lock.
                if state.reopen.is_set() or device is None:
                    state.reopen.clear()
                    with state.lock:
                        state.device = None
                    if device is not None:
                        device.close()
                        device = None
                    try:
                        device = BoundedAX206Device.open(index=args.index, backend=backend)
                        orient(rendered, (device.width, device.height), args.rotation)
                        logging.info('AX206 connected: %dx%d (%s)', device.width, device.height, backend_name)
                    except ValueError:
                        if device is not None:
                            device.close()
                            device = None
                        raise  # invalid theme/resolution is not a transient USB error
                    except Exception:
                        if device is not None:
                            device.close()
                            device = None
                        logging.exception('Display unavailable; retrying in five seconds.')
                        state.changed.wait(5)
                        state.changed.clear()
                        continue
                    with state.lock:
                        state.device = device
                        # Suspend may have arrived while open() was running.
                        if state.paused.is_set() or state.stopped.is_set():
                            try:
                                device.power_off()
                            except Exception:
                                logging.exception('Could not darken newly opened display.')
                            continue
                pixels = image_to_rgb565(orient(rendered, (device.width, device.height), args.rotation))
                try:
                    # Each lock hold contains one bounded USB command only.
                    with state.lock:
                        if state.paused.is_set() or state.stopped.is_set():
                            continue
                        device.blit(pixels)
                    with state.lock:
                        if state.paused.is_set() or state.stopped.is_set():
                            continue
                        device.set_backlight(7)
                except Exception:
                    logging.exception('Display transfer failed; reopening on next attempt.')
                    state.reopen.set()
                    state.changed.wait(5)
                    state.changed.clear()
                    continue
                state.changed.wait(1)
                state.changed.clear()
        except KeyboardInterrupt:
            print('Stopped.')
        finally:
            state.darken(shutdown=True)
            with state.lock:
                state.device = None
            if device is not None:
                device.close()
            for source in sources:
                try:
                    source.close()
                except Exception:
                    logging.exception('Could not close sensor source.')

if __name__ == '__main__':
    main()
