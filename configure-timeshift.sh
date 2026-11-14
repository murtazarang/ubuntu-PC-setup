#!/usr/bin/env bash
set -Eeuo pipefail
if (( EUID == 0 )); then echo 'Run as the desktop user.' >&2; exit 1; fi
[[ $(findmnt -n -o FSTYPE /) == btrfs && $(findmnt -n -o FSROOT /) == /@ ]] || { echo 'Expected Btrfs root subvolume @; finish the installation instructions first.' >&2; exit 1; }
command -v timeshift >/dev/null || { echo 'Install timeshift first.' >&2; exit 1; }
rootdev=$(findmnt -n -o SOURCE /); rootdev=${rootdev%%\[*}
uuid=$(sudo blkid -s UUID -o value "$rootdev")
[[ -n $uuid ]] || { echo 'Cannot identify root filesystem UUID.' >&2; exit 1; }
sudo mkdir -p /etc/timeshift
sudo /usr/bin/python3 - "$uuid" <<'PY'
import json,os,sys,tempfile
p='/etc/timeshift/timeshift.json'; uuid=sys.argv[1]
if os.path.exists(p):
 with open(p) as f: d=json.load(f)
 if d.get('do_first_run') == 'false':
  if d.get('btrfs_mode') != 'true' or d.get('backup_device_uuid') != uuid:
   raise SystemExit('Existing Timeshift configuration differs; refusing to overwrite it.')
  print('Existing matching Timeshift configuration retained.'); sys.exit(0)
else: d={}
d.update({'backup_device_uuid':uuid,'parent_device_uuid':'','do_first_run':'false','btrfs_mode':'true','include_btrfs_home':'false','include_btrfs_home_for_backup':'false','include_btrfs_home_for_restore':'false','stop_cron_emails':'true','schedule_daily':'true','count_daily':'5','schedule_weekly':'true','count_weekly':'2','schedule_monthly':'false','schedule_hourly':'false','schedule_boot':'false','exclude':[],'exclude-apps':[]})
fd,tmp=tempfile.mkstemp(dir='/etc/timeshift'); os.fchmod(fd,0o600)
with os.fdopen(fd,'w') as f: json.dump(d,f,indent=2); f.write('\n')
os.replace(tmp,p)
PY
sudo timeshift --create --btrfs --comments 'Initial setup' --tags O
sudo timeshift --list --btrfs
echo 'Btrfs snapshots exclude the separate /boot and /home. Maintain separate backups.'
