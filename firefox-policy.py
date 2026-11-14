#!/usr/bin/env python3
"""Merge requested Firefox add-on policies without deleting unrelated settings."""
import json, sys
if len(sys.argv) > 2 or (len(sys.argv) == 2 and sys.argv[1] != '--release'):
    raise SystemExit('Usage: firefox-policy.py [--release]')
src = json.load(sys.stdin)
if not isinstance(src, dict): raise SystemExit('Invalid existing policy root')
p = src.setdefault('policies', {})
if not isinstance(p, dict): raise SystemExit('Invalid existing policies object')
if len(sys.argv) > 1 and sys.argv[1] == '--release':
    u = p.get('3rdparty', {}).get('Extensions', {}).get('uBlock0@raymondhill.net', {})
    if not isinstance(u, dict): raise SystemExit('Invalid managed uBlock settings')
    u.pop('toOverwrite', None)
    json.dump(src, sys.stdout, indent=2); print(); raise SystemExit(0)
addons = p.setdefault('ExtensionSettings', {})
for ident, slug in [('uBlock0@raymondhill.net','ublock-origin'),('seventv-next@7tv.app','7tv-new'),('{76ef94a4-e3d0-4c6f-961a-d38a429a332b}','ttv-lol-pro')]:
    addons.setdefault(ident, {}).update({'installation_mode':'normal_installed','install_url':f'https://addons.mozilla.org/firefox/downloads/latest/{slug}/latest.xpi'})
third = p.setdefault('3rdparty', {}).setdefault('Extensions', {})
desired={
  'userSettings':[['advancedUserEnabled','true']],
  'advancedSettings':[['userResourcesLocation','https://raw.githubusercontent.com/pixeltris/TwitchAdSolutions/master/vaft/vaft-ublock-origin.js']],
  'toOverwrite':{
    'filters':['twitch.tv##+js(twitch-videoad)'],
    'filterLists':['user-filters','ublock-filters','ublock-badware','ublock-privacy','ublock-abuse','ublock-unbreak','ublock-quick-fixes','easylist','easyprivacy','urlhaus-1','plowe-0','fanboy-cookiemonster','ublock-cookies-easylist','easylist-annoyances','ublock-annoyances','fanboy-social']
  }
}
released={k:v for k,v in desired.items() if k != 'toOverwrite'}
existing=third.get('uBlock0@raymondhill.net')
if existing is not None and existing not in (desired,released):
    raise SystemExit('Different managed uBlock settings found; refusing to overwrite them')
if existing is None: third['uBlock0@raymondhill.net']=desired
json.dump(src,sys.stdout,indent=2); print()
