# AX206 portrait display: Windows service

For the single RTX 3080 PC, AX206 USB `1908:0102`, physically mounted with its original right edge at the top. Default framebuffer rotation: 270 degrees counterclockwise. Uses the GPL-2.0-or-later mechcow dashboard implementation pinned to `11280756789f1d61b80b49383b255acde62a9c60`, with the included portrait theme. See [upstream](https://github.com/mechcow/win-ax206-display) and `LICENSE`.

## Fresh install

Open **PowerShell as administrator**, under your usual Windows account:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1 | iex
```

The standalone installer supplies its own private uv 0.13.9 from the [official release](https://github.com/astral-sh/uv/releases/tag/0.13.9), verifies the published SHA-256, and reuses it on subsequent runs. It needs neither the main PC setup, WinGet, Git, Python nor PowerShell 7. This copy lives under protected `Program Files\AX206Panel\tools`; existing uv installations and PATH are unchanged. Requires x64 Windows and 64-bit administrator PowerShell. See [official uv installation methods](https://docs.astral.sh/uv/getting-started/installation/#github-releases).

USB access and sensor drivers are separate prerequisites: this script never installs or changes USB drivers or PawnIO. On a genuinely fresh PC these still require your explicit manual setup; installing the service alone does not establish hardware readiness.

## Patch an existing installation

Close any manually started foreground panel with Ctrl+C first. Do not uninstall the working USB driver or PawnIO. Run in administrator PowerShell:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/patch.ps1 | iex
```

Both entry points use the **same canonical service installer**. The patch imports your existing `portrait.yaml` and scheduled rotation, installs the new runtime, then replaces only this project's recognized scheduled task. Unrelated tasks/processes are not removed. A failed service start attempts to restore the previous startup. Legacy files remain as a backup, but the obsolete task is removed after successful migration. Do not run the old `autostart.ps1` again.

The service accepts text, gauge, bar and sparkline widgets using built-in Windows font aliases. Themes with external files, images, slideshows, agendas or arbitrary fonts are rejected before rendering: the original theme and startup remain unchanged. This prevents privileged file/network access through an imported theme. The synthetic preview is validated before changing startup; it cannot establish sensor or display functionality.

## Behavior and security

`AX206Panel` is an automatic Windows service, running as **LocalSystem** at boot without a sign-in or terminal. Its interpreter, dependencies, source and theme live in administrator-owned `%ProgramFiles%\AX206Panel\releases\...`. Runtime code is not loaded from your old LocalAppData installation or uv cache. Logs are under `%ProgramData%\AX206Panel\service.log` (rotated).

The service accepts SCM suspend/resume/shutdown controls, attempts to switch off the backlight before sleep/shutdown, and reopens USB after resume. It retries unavailable/disconnected USB every five seconds and retries hardware sensor discovery every 30 seconds when temperatures are missing. SCM recovery restarts failed processes after 5, 15, then 60 seconds. These are software attempts: powered motherboard USB, firmware, abrupt power loss and driver behavior can prevent a guaranteed backlight-off.

Setup needs existing `uv` and the working device/PawnIO drivers. It installs Python 3.11, pywin32, the pinned upstream software and LibreHardwareMonitor libraries; it does **not** install or replace USB or PawnIO drivers. LocalSystem is used for privileged hardware sensor access. The service loads its USB backend only from Windows System32, not per-user package-manager folders. A working system-wide libusb0.dll or libusb-1.0.dll is required; absence is an actionable error, not a reason to modify drivers automatically. Actual sensor/USB access under that account still requires verification on the physical PC.

## Status and logs

```powershell
Get-Service AX206Panel
Get-Content "$env:ProgramData\AX206Panel\service.log" -Tail 60
```

```powershell
Restart-Service AX206Panel
Stop-Service AX206Panel
Start-Service AX206Panel
```

For diagnostics, locate the installed release:

```powershell
$r = (Get-Content "$env:ProgramFiles\AX206Panel\current.json" | ConvertFrom-Json).release
& "$r\Run.ps1" -Action Sensors
```

`Info` and `TestPattern` require stopping the service first, then restarting afterwards. `Preview` writes a synthetic image to `%TEMP%\ax206-preview.png`. A running service alone does not establish that sensors are available: missing readings remain `--`.

To remove startup while preserving files/settings/logs:

```powershell
& "$r\Service.ps1" -Action Remove
```

## Validation

Python tests cover simulated reconnects, bounded USB transfers, rotation, SCM callback mapping and shutdown state. Windows CI executes safe PowerShell guard/delegation tests and the Windows mutex test; the runtime-staging tests also install the real Python/dependencies and exercise fresh, interrupted and repeated staging in temporary directories. CI does not register the actual service or access GPU sensors/USB hardware. Physical boot, sleep/resume and sensor behavior are not claimed verified.

## Source references

- [Microsoft: service control handler](https://learn.microsoft.com/en-us/windows/win32/services/service-control-handler-function)
- [Microsoft: HandlerEx power events](https://learn.microsoft.com/en-us/windows/win32/api/winsvc/nc-winsvc-lphandler_function_ex)
- [pywin32 service event example](https://github.com/mhammond/pywin32/blob/main/win32/Demos/service/serviceEvents.py)
- [uv managed Python installation](https://docs.astral.sh/uv/guides/install-python/)
- [Microsoft sc failure](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/sc-failure)

Python environment creation uses the protected uv-managed interpreter with [`python -m venv --copies --without-pip`](https://docs.python.org/3.11/library/venv.html). Package installation remains through `uv pip`; `uv venv --copies` is not a supported command.

### Interrupted uv bootstrap

If Windows or the terminal stops during extraction, the next run may report that the private uv file is not owned by SYSTEM/Administrators. The installer refuses to execute that incomplete file. In administrator PowerShell, remove only the private bootstrap tools directory, then rerun the same install or patch command:

```powershell
Remove-Item -LiteralPath "$env:ProgramFiles\AX206Panel\tools" -Recurse -Force
```

This directory contains only the private uv bootstrap, not the service interpreter, display settings, logs or drivers. Do not remove the `releases` directory or `current.json`.
