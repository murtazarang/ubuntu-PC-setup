# AX206 USB display: portrait CPU / GPU / RAM

Independent Windows setup for USB **1908:0102**. It does not require AIDA64, change the main PC installer, install PawnIO, change USB drivers, disable antivirus, or alter fan control. PawnIO is assumed already installed. Close AIDA64 or other software using the screen first.

This adapts the **existing dark gauge dashboard** from [mechcow/win-ax206-display](https://github.com/mechcow/win-ax206-display/blob/11280756789f1d61b80b49383b255acde62a9c60/themes/default.yaml), rearranging its temperature gauges into a 320×480 portrait layout. CPU and GPU temperatures, their load percentages, RAM usage and a clock fit the small screen. Theme and software license: GPL-2.0-or-later; full license included. This is a small source-based upstream project, not a commercial turnkey driver.

## Install directly from GitHub

On the **Ryzen 5700G / single RTX 3080 PC**, open Windows PowerShell or PowerShell 7 **as administrator** for hardware sensor access and paste this one line. No Git installation, clone or manual file download is needed:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1 | iex
```

This downloads the current repository snapshot, runs only this display's setup, and registers automatic startup for your next Windows sign-in. It does not start a second display process now or disturb one already running. After setup returns, you can close the terminal. It executes code from this repository. `uv` from the existing PC setup must be available; otherwise use [its official Windows installation instructions](https://docs.astral.sh/uv/getting-started/installation/), then reopen PowerShell. The launcher requires only Windows PowerShell 5.1 or newer, not PowerShell 7. Setup executes in a child PowerShell process with `-ExecutionPolicy Bypass`; this does not change your saved execution policy. Organization-enforced Group Policy still takes precedence.

The launcher is named `install.ps1`, distinct from the existing `Run.ps1` because Windows filenames are case-insensitive. It retains its downloaded setup under `%LOCALAPPDATA%\AX206Panel\setup-runs`, copies the runner to `%LOCALAPPDATA%\AX206Panel\Run.ps1`, and preserves your existing `portrait.yaml`. Rerunning setup reuses the existing Python environment and upstream libraries; it still checks Python dependencies. It does not install or change USB drivers or PawnIO.

To select a different rotation on first installation, use:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1))) -Rotation 90
```

The older `-SetupOnly` argument remains accepted for compatibility; setup now always returns without starting a foreground display. Changing an already-registered startup rotation requires removing its task first, then installing with the desired rotation. Existing tasks are not silently overwritten.

For manual diagnostics without downloading anything, use the commands below. **Do not run Panel, Info or TestPattern while another display process owns the USB device.** The final command starts a foreground panel only for manual testing:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action Info
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action TestPattern
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action Sensors
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Rotation 270
```

If you already have a local copy of this folder, `.\Setup.ps1` also registers automatic startup by default. `.\Run.ps1` remains available for manual foreground use. A custom `-InstallDir` is accepted by the launcher, setup and runner; use the same directory each time. The launcher prints exact restart and diagnostic commands for your chosen directory.

1. Setup downloads a pinned upstream source archive, uses uv to create a dedicated Python 3.11 environment, and downloads the LibreHardwareMonitor .NET libraries through upstream's NuGet helper. It reuses an existing environment and libraries on rerun. It does **not** reinstall PawnIO. Dependencies are constrained by upstream, not fully locked; NuGet chooses its latest stable library on the first successful setup.
2. **Info reads the actual resolution from the USB display.** A reported 480×320 needs rotation 90 or 270. The default **270** rotates the framebuffer clockwise to compensate for your portrait-left mounting (the original landscape right edge is at the top). If the result is upside down, quit with Ctrl+C and use `-Rotation 90`. A device reporting 320×480 uses 0 or 180. Other sizes deliberately fail rather than stretch the dashboard.
3. TestPattern displays upstream color bars. Sensors lists the actual available hardware readings. Missing temperatures mean sensor access needs checking, not that the CPU is at zero degrees.
4. The registered task starts the panel at one update per second after this user signs in, without an open terminal. Manual `Run.ps1` instead runs in the foreground; Ctrl+C stops that manual instance and turns off its backlight. On unplug/error the panel stops; reconnect and restart it. There is no tray icon or automatic USB reconnection.

For a preview without USB writes:
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action Preview
```
This saves `%LOCALAPPDATA%\AX206Panel\preview.png` using **synthetic demonstration readings**, not live temperatures. You can edit `%LOCALAPPDATA%\AX206Panel\portrait.yaml`; rerunning Setup preserves that theme. Restart the panel after editing. `-InstallDir` is supported on both scripts; use the same path for each.

## USB driver, only if Info cannot open the display

Follow [upstream's driver instructions](https://github.com/mechcow/win-ax206-display/blob/11280756789f1d61b80b49383b255acde62a9c60/README.md). An existing working AX206/libusb-win32 driver needs no replacement. If a driver is missing, use [official Zadig](https://zadig.akeo.ie/), select only the display with ID **1908:0102**, and select **libusb-win32** as recommended upstream for AIDA64 compatibility. Do not replace a keyboard, mouse or unrelated USB device's driver. Driver changes remain manual. Do not disable security software or download the seller's unknown archive. A missing `libusb0.dll` is a separate backend availability error; follow the upstream backend instructions rather than copying arbitrary DLLs into Windows system folders.

## Sensor limitations

Missing values display `--`. CPU temperature is upstream's selected package/core measurement, not every individual core. Upstream prefers NVIDIA over AMD over Intel for its generic GPU keys. **Its sensor mapping does not preserve separate identities for two GPUs of the same vendor.** This runner hides GPU values in that case rather than combine readings from a dual-RTX-3060 system; CPU/RAM still work. It does not yet provide a trustworthy dual-GPU dashboard. View `-Action Sensors` for the raw hardware listing. Intel ARC sensor availability depends on what LibreHardwareMonitor exposes on that machine.

## Verification and sources

Locally verified: six isolated Python tests covering rotation corner placement, native portrait dimensions, rejection of unsupported resolution, suppression of ambiguous same-vendor GPU readings and cleanup on failure; synthetic rendering with the pinned upstream renderer. **No Windows installer, USB transfer, PawnIO access, or real temperature readings were tested here.** No claim of end-to-end hardware validation.

```powershell
& "$env:LOCALAPPDATA\AX206Panel\.venv\Scripts\python.exe" -m unittest discover -s .\tests -v
```

Source interface reviewed: upstream `device.py`, `framebuffer.py`, `render/engine.py`, `render/widgets.py`, `sensors/lhm.py`, `tools/fetch_lhm.py` at commit `11280756789f1d61b80b49383b255acde62a9c60`. The wrapper rotates before RGB565 conversion; it never asks the upstream application to resize a portrait theme into a landscape framebuffer. Theme design and rendering stay upstream; no hotpath patch to upstream code is needed.


## Automatic startup after Windows sign-in

Display setup now registers automatic startup by default. Run the setup in **PowerShell as administrator under your normal Windows account**. Setup does not start a second display process or terminate an existing one. After your next sign-in, the display starts without a terminal.

For an already-installed, working display, add startup without rerunning setup:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/autostart.ps1 | iex
```

This registers a Task Scheduler task for your account at sign-in, using the existing installation and portrait rotation 270. It runs without an open terminal, with elevated privileges for sensor access, and saves no password. It does **not** start another copy now or interrupt your current display. If your current foreground display is running in a separate terminal, keep that terminal open until sign-out if you want the display to remain on during this session. After your next sign-in, do not also launch `Run.ps1`. USB drivers and PawnIO are untouched.

Status:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/autostart.ps1))) -Action Status
```

Remove automatic startup (administrator PowerShell):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/autostart.ps1))) -Action Remove
```

Removal only unregisters this task; it does not terminate a running display or delete installation files. If startup fails, inspect `%LOCALAPPDATA%\AX206Panel\autostart.log`. The log keeps one previous copy when it grows beyond 2 MB at startup. The USB display must be connected at sign-in; automatic USB reconnection is not implemented. The task runs while this user is signed in, not before login. Signing in as a different administrator registers that administrator's task instead, so use your normal account.

Task Scheduler details: [sign-in trigger](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasktrigger), [interactive elevated principal](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtaskprincipal), [no time limit and IgnoreNew](https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/new-scheduledtasksettingsset). The `pythonw.exe` process avoids a console window; stdout and errors are redirected before running the panel.
