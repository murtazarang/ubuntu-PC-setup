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
same hardware selection. The desktop stage can take hours to download Wikipedia. Colibri models are chosen and downloaded later in its UI; model use remains local by default and hosted providers in OMP are not disabled.

The installed applications include Steam, Firefox, Stremio,
Spotify, VS Code, PowerToys, Colibri and the
supplied SignalRGB installer. These
installers may display their own prompts. Steam games use native Windows
graphics APIs; no Proton is needed. PowerToys Run targets Win+F2, PowerToys
Awake provides an on-demand keep-awake switch, and Windows clipboard history
uses Win+V. Everything and the EverythingPowerToys plugin provide indexed search in PowerToys Run; actual integration still needs a Windows smoke test. The setup changes the current user's application settings; the separate HDD is not formatted.

Oh My Pi is configured to use the complete scientific, scientific-writer and
Education Agent Skills libraries and a dedicated locally installed OpenZIM MCP bridge. The Wikipedia archive is checked against Kiwix's SHA-256 before registration.
The full English June 2026 Wikipedia text-only ZIM requires about 49 GiB.
The model and archive together can need well over 120 GiB of available SSD
space. To place the archive elsewhere pass `-ArchiveDirectory D:\YourFolder`
to the Desktop stage. An interrupted archive download can be resumed by
rerunning `Install-Reference.ps1` with the same directory.

Firefox uses installation-wide managed add-on policies. To avoid changing another Windows user's Firefox, initialization stops if it detects another ordinary Windows profile; unregistered custom Firefox profiles may not be detected. Existing uBlock profiles are protected from automatic filter replacement; review the script output if an existing profile is detected. After first launch, let the three extensions
load, close Firefox and run `./Configure-Firefox.ps1 -Release` from an elevated
terminal. This removes the one-time enforced filter-list values so later user
edits persist; the advanced Twitch resource URL remains managed.

## Checks needed on each actual machine

Verify the correct GPU driver and reboot, `nvidia-smi` on NVIDIA, Windows GPU
driver status on Intel, both 3060s on the dual system, then start the local model.
Confirm its `/v1/models` endpoint and run a tool-using test in both Oh My Pi and
Colibri. Verify OpenZIM search and source retrieval offline, plus all Firefox
extensions and settings, Win+F2, Win+V, Awake, SignalRGB and Steam.
None of these hardware, GUI, installer, archive download, or end-to-end AI tests
has been run by the author of these scripts.

Python tests check configuration merges in isolation; mocked PowerShell tests run in Windows CI. Neither executes real installers, GPU inference, Firefox, or a full offline MCP query. Sources: [OpenZIM MCP](https://github.com/cameronrye/openzim-mcp),
[OMP](https://github.com/can1357/oh-my-pi), [Colibri](https://github.com/JustVugg/colibri),
[PowerToys DSC](https://learn.microsoft.com/en-us/windows/powertoys/dsc-configure/microsoft-dsc).

## Colibri replaces Paseo, Strata and XeStrata

The Desktop stage now installs Colibri v2.1.0 and its **built-in browser UI**.
It does not install Paseo and does not download a model. This is not the separate
Tauri shell: that shell does not manage inference or model downloads.

Start **Colibri UI** from the desktop shortcut. It invokes upstream's `coli ui`
directly, using the installed Python environment; no custom launcher or UI is added.
The UI is local-only at `http://127.0.0.1:8790`. Its Models page downloads models
with progress and resume. Choose a model there after reviewing its disk and
memory requirements. A model download remains your action in the UI.

**Windows limitation:** upstream's UI model-switching service currently supports
Linux only. After downloading, use upstream's existing CLI in PowerShell:

```powershell
$install = "$env:LOCALAPPDATA\Colibri-PC-Setup\v2.1.0-vulkan"
$env:COLI_VULKAN = '1'
$env:COLI_CUDA = '0'
$env:COLI_NO_OMP_TUNE = '1'
# For the dual RTX 3060 PC only:
# $env:COLI_VK_DEV2 = 'auto'
& "$install\venv\Scripts\python.exe" "$install\app\coli" serve --host 127.0.0.1 --port 8000 --model 'C:\path\to\downloaded-model'
```

Keep the UI and model processes open while using them. To change models on
Windows, stop the model with Ctrl+C and run the upstream command with the new
folder. The OpenAI-compatible endpoint is `http://127.0.0.1:8000/v1`. Once running,
`Connect-LocalModel.ps1 -Port 8000` (run from PowerShell 7, `pwsh`) can configure OMP; it preserves conflicting
existing provider configuration rather than overwriting it.

Hardware profiles:
- **RTX 3080 10 GB:** default Vulkan with upstream memory planning; no CUDA toolkit or overlay is needed.
- **Two RTX 3060 12 GB:** default Vulkan with `COLI_VK_DEV2=auto` enabling the
  upstream second-device tier. VRAM is not presented as one unified allocation.
  Upstream has not measured real multi-GPU Vulkan performance; verify both device
  names in engine output.
- **Intel Arc B580 12 GB:** Vulkan, no CUDA overlay. Upstream chooses the preferred
  discrete device; verify the log identifies B580 rather than integrated graphics.

All profiles retain the installed GPU drivers. No CUDA toolkit, WSL or model
weights are installed. All three profiles use Vulkan, including Qwen3.8. Do not infer performance from
combined RAM/VRAM alone.

Sources: [Windows release installation](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/windows.md),
[UI](https://github.com/JustVugg/colibri/blob/v2.1.0/ui/README.md),
[Vulkan devices](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/vulkan.md),
[desktop shell limits](https://github.com/JustVugg/colibri/blob/v2.1.0/desktop/README.md).
