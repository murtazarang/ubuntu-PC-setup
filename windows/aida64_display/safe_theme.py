"""Reject file/network-capable theme features before privileged rendering.

The service supports the supplied portrait's text/gauge/bar/sparkline widgets.
It deliberately does not import images, slideshows, agendas or external fonts.
An unsupported existing theme is preserved and migration stops, never replaced.
"""
from pathlib import Path
import yaml

FONTS = {'Segoe UI', 'Segoe UI Bold', 'Segoe UI Light', 'Consolas',
         'Consolas Bold', 'Arial', 'Arial Bold'}
ROOT_KEYS = {'name', 'size', 'background', 'defaults', 'widgets'}
STYLE_KEYS = {'font', 'font_size', 'color'}
WIDGET_KEYS = STYLE_KEYS | {'type', 'pos', 'text', 'sensor', 'format', 'anchor',
                          'size', 'min', 'max', 'background', 'history', 'width'}


def validate_theme(path):
    path = Path(path)
    if path.stat().st_size > 65536:
        raise ValueError('Theme is too large for safe service import (64 KiB limit)')
    data = yaml.safe_load(path.read_text(encoding='utf-8-sig'))
    if not isinstance(data, dict) or set(data) - ROOT_KEYS:
        raise ValueError('Unsupported theme keys; original theme was preserved')
    if data.get('size') not in ([320, 480], [480, 320]):
        raise ValueError('Service theme must have a supported portrait/framebuffer size')
    defaults = data.get('defaults') or {}
    if not isinstance(defaults, dict) or set(defaults) - STYLE_KEYS:
        raise ValueError('Unsupported theme defaults')
    widgets = data.get('widgets')
    if not isinstance(widgets, list) or not 1 <= len(widgets) <= 100:
        raise ValueError('Expected 1–100 service widgets')
    for item in [defaults] + widgets:
        if not isinstance(item, dict):
            raise ValueError('Expected widget/default mapping')
        if item is not defaults and (set(item) - WIDGET_KEYS or item.get('type') not in {'text','gauge','bar','sparkline'}):
            raise ValueError('Service import supports text, gauge, bar and sparkline only; no external files or network sources')
        if 'font' in item and item['font'] not in FONTS:
            raise ValueError('Only bundled Windows font aliases are permitted in service themes')
        if 'font_size' in item and (type(item['font_size']) is not int or not 1 <= item['font_size'] <= 128):
            raise ValueError('Invalid service font size')
        for key, value in item.items():
            if isinstance(value, (dict, set)) or (isinstance(value, list) and (len(value) != 2 or any(type(v) not in (int,float) or abs(v)>2000 for v in value))):
                raise ValueError('Nested or oversized theme values are not permitted')
            if isinstance(value, str) and len(value)>1000:
                raise ValueError('Theme value too long')
        size = item.get('size')
        if type(size) in (int,float) and not 1 <= size <= 2000:
            raise ValueError('Widget size exceeds service limit')
    return data


if __name__ == '__main__':
    import sys
    validate_theme(sys.argv[1])
