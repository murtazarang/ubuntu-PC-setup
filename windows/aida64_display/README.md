# AX206 USB display: portrait CPU / GPU / RAM

Independent Windows setup for USB **1908:0102**. It does not require AIDA64, change the main PC installer, install PawnIO, change USB drivers, disable antivirus, register startup, or alter fan control. PawnIO is assumed already installed. Close AIDA64 or other software using the screen first.

This adapts the **existing dark gauge dashboard** from [mechcow/win-ax206-display](https://github.com/mechcow/win-ax206-display/blob/11280756789f1d61b80b49383b255acde62a9c60/themes/default.yaml), rearranging its temperature gauges into a 320×480 portrait layout. CPU and GPU temperatures, their load percentages, RAM usage and a clock fit the small screen. Theme and software license: GPL-2.0-or-later; full license included. This is a small source-based upstream project, not a commercial turnkey driver.

## Install and start directly from GitHub

On the **Ryzen 5700G / single RTX 3080 PC**, open Windows PowerShell or PowerShell 7 **as administrator** for hardware sensor access and paste this one line. No Git installation, clone or manual file download is needed:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1 | iex
```

This downloads the current repository snapshot, runs only this display's setup, and starts the portrait dashboard. It executes code from this repository. `uv` from the existing PC setup must be available; otherwise use [its official Windows installation instructions](https://docs.astral.sh/uv/getting-started/installation/), then reopen PowerShell. The launcher requires only Windows PowerShell 5.1 or newer, not PowerShell 7. Setup and the display runner execute in a child PowerShell process with `-ExecutionPolicy Bypass`; this does not change your saved execution policy. Organization-enforced Group Policy still takes precedence.

The launcher is named `install.ps1`, distinct from the existing `Run.ps1` because Windows filenames are case-insensitive. It retains its downloaded setup under `%LOCALAPPDATA%\AX206Panel\setup-runs`, copies the runner to `%LOCALAPPDATA%\AX206Panel\Run.ps1`, and preserves your existing `portrait.yaml`. Rerunning setup reuses the existing Python environment and upstream libraries; it still checks Python dependencies. It does not install or change USB drivers or PawnIO.

For setup without starting the screen, or to pass a different rotation, use the parameterized form:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1))) -SetupOnly
# Alternatively replace -SetupOnly with -Rotation 90 if the picture is upside down.
```

After setup, start again or diagnose the display without downloading anything:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action Info
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action TestPattern
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Action Sensors
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\AX206Panel\Run.ps1" -Rotation 270
```

If you already have a local copy of this folder, `.\Setup.ps1` followed by `.\Run.ps1` still works. A custom `-InstallDir` is accepted by the launcher, setup and runner; use the same directory each time. The launcher prints exact restart and diagnostic commands for your chosen directory.

1. Setup downloads a pinned upstream source archive, uses uv to create a dedicated Python 3.11 environment, and downloads the LibreHardwareMonitor .NET libraries through upstream's NuGet helper. It reuses an existing environment and libraries on rerun. It does **not** reinstall PawnIO. Dependencies are constrained by upstream, not fully locked; NuGet chooses its latest stable library on the first successful setup.
2. **Info reads the actual resolution from the USB display.** A reported 480×320 needs rotation 90 or 270. The default **270** rotates the framebuffer clockwise to compensate for your portrait-left mounting (the original landscape right edge is at the top). If the result is upside down, quit with Ctrl+C and use `-Rotation 90`. A device reporting 320×480 uses 0 or 180. Other sizes deliberately fail rather than stretch the dashboard.
3. TestPattern displays upstream color bars. Sensors lists the actual available hardware readings. Missing temperatures mean sensor access needs checking, not that the CPU is at zero degrees.
4. Panel runs in the foreground at one update per second. Keep the terminal open. Ctrl+C stops it and turns off its backlight. On unplug/error it stops; reconnect and rerun. No tray or automatic startup is configured by this wrapper.

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
