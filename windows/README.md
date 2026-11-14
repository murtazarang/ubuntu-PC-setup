# Native Windows PC setup

**Status: draft, not yet validated on Windows.** The PowerShell and installers have
not been run on Windows or on the specified GPUs. Do not treat the scripts as
verified until tested. No disk partitioning, formatting, WSL, Btrfs or Timeshift
is performed.

## Short launcher

Open Windows PowerShell as administrator, then enter:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/run.ps1 | iex
```

The launcher asks which PC and stage, gets the required files automatically,
and runs that stage. Run it again after the driver step and reboot, choosing
Desktop. It needs internet and WinGet. This is still an unverified draft. The launcher prints the retained setup folder so its recovery helpers remain accessible after execution.

## Intended workflow

Install Windows 11 and create the desired local account yourself. The third
machine's HDD is left entirely untouched. Open a terminal in this directory as
that account, run `Bootstrap.ps1` to acquire PowerShell 7, and open **PowerShell
7 as administrator**. Use one of these hardware names:

- 5700G + one RTX 3080: `NvidiaSingle`
- i5-13400 + Arc B580: `Intel`
- 2700X + two RTX 3060s: `NvidiaDual`

Run `./Setup.ps1 -Stage Drivers -Hardware NvidiaSingle`, substituting the
appropriate hardware name. The stage runs Windows Update and installs the NVIDIA
App on NVIDIA machines or Intel Driver & Support Assistant on the Intel machine.
Open the installed vendor app, install its recommended graphics driver, and
reboot. The script does not install a pinned driver automatically. Then run `./Setup.ps1 -Stage Desktop -Hardware NvidiaSingle` with the
same hardware selection. The desktop stage can take hours to download models
and Wikipedia. NVIDIA uses IQ2_XS for one GPU or IQ3_XXS with both GPUs; Intel
uses XeStrata Gyro-S. Model use remains local by default; hosted providers are
not disabled.

The installed applications include Steam, Firefox, Stremio, Mailspring,
Spotify, VS Code, PowerToys, ArtCraft Studio, the selected Paseo beta, the
exact FanControl V285 installer and the supplied SignalRGB installer. These
installers may display their own prompts. Steam games use native Windows
graphics APIs; no Proton is needed. PowerToys Run targets Win+F2, PowerToys
Awake provides an on-demand keep-awake switch, and Windows clipboard history
uses Win+V. Everything and the EverythingPowerToys plugin provide indexed search in PowerToys Run; actual integration still needs a Windows smoke test. User-level data and the separate HDD are not modified by design.

Oh My Pi is configured to use the complete scientific, scientific-writer and
Education Agent Skills libraries and the locally cached OpenZIM MCP bridge.
The full English June 2026 Wikipedia text-only ZIM requires about 49 GiB.
The model and archive together can need well over 120 GiB of available SSD
space. To place the archive elsewhere pass `-ArchiveDirectory D:\YourFolder`
to the Desktop stage. An interrupted archive download can be resumed by
rerunning `Install-Reference.ps1` with the same directory.

Firefox uses managed add-on policies. Existing uBlock profiles are protected from automatic filter replacement; review the script output if an existing profile is detected. After first launch, let the three extensions
load, close Firefox and run `./Configure-Firefox.ps1 -Release` from an elevated
terminal. This removes the one-time enforced filter-list values so later user
edits persist; the advanced Twitch resource URL remains managed.

## Checks needed on each actual machine

Verify the correct GPU driver and reboot, `nvidia-smi` on NVIDIA, Windows GPU
driver status on Intel, both 3060s on the dual system, then start the local model.
Confirm its `/v1/models` endpoint and run a tool-using test in both Oh My Pi and
Paseo. Verify OpenZIM search and source retrieval offline, plus all Firefox
extensions and settings, Win+F2, Win+V, Awake, FanControl, SignalRGB and Steam.
None of these hardware, GUI, installer, archive download, or end-to-end AI tests
has been run by the author of these scripts.

The eleven Python unit tests check configuration merges in isolation only:
`python -m unittest discover -s windows/tests`. They do not exercise PowerShell,
installers or actual Windows. Sources: [OpenZIM MCP](https://github.com/cameronrye/openzim-mcp),
[OMP](https://github.com/can1357/oh-my-pi), [Strata](https://github.com/Niko1221/Strata),
[XeStrata](https://github.com/MistVVK/XeStrata),
[PowerToys DSC](https://learn.microsoft.com/en-us/windows/powertoys/dsc-configure/microsoft-dsc).
