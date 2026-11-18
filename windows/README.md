# Native Windows PC setup

**Status: Windows CI tested; full PC setup and GPU inference remain unverified.**
PowerShell parsing, safe runtime fixtures, and the real Colibri release/dependency/UI
installation have run on Windows CI. The full desktop installation, large model
downloads and inference have not been exercised on these three PCs. No disk
partitioning, formatting, WSL, Btrfs or Timeshift is performed.

The implementation passed [Windows and Linux CI on November 18, 2026](https://github.com/murtazarang/ubuntu-PC-setup/actions/runs/44328376158)
at commit `4dc0671`; the subsequent change only clarifies this coverage.

## Short launcher

Open Windows PowerShell as administrator, then enter:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/run.ps1 | iex
```

The launcher asks which PC and stage, gets the required files automatically,
and runs that stage. Run it again after the driver step and reboot, choosing
Desktop. It needs internet and WinGet. Hardware-specific operation still needs verification. The launcher prints the retained setup folder so its recovery helpers remain accessible after execution.

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
same hardware selection. The desktop stage can take hours to download Wikipedia. The assigned Colibri text and image models also download during setup. Model use remains local by default; hosted providers in OMP are not disabled.

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
The full desktop installation, physical GPUs, model inference, Firefox GUI and
end-to-end AI integrations still require verification on your PCs.

Python tests check configuration merges in isolation; mocked PowerShell tests run in Windows CI. The Colibri smoke test additionally downloads and verifies the real release, installs its Python dependencies, checks reruns and starts its upstream UI without model weights. It does not test GPU inference or a full offline MCP query. Sources: [OpenZIM MCP](https://github.com/cameronrye/openzim-mcp),
[OMP](https://github.com/can1357/oh-my-pi), [Colibri](https://github.com/JustVugg/colibri),
[PowerToys DSC](https://learn.microsoft.com/en-us/windows/powertoys/dsc-configure/microsoft-dsc).

## Colibri replaces Paseo, Strata and XeStrata

The Desktop stage now installs Colibri v2.1.0 and its **built-in browser UI**.
It does not install Paseo. It downloads and verifies the assigned model below. This is not the separate
Tauri shell: that shell does not manage inference or model downloads.

The installer creates exactly two desktop shortcuts:
- **Colibri Serve**: selected text model at `127.0.0.1:8000`, with the Serve icon badge.
- **Colibri Serve Image**: Qwen-Image-2.1 at `127.0.0.1:8001`, with the Serve Img icon badge.

**Colibri Serve** starts upstream `coli serve` on port 8000 in its own terminal,
then upstream's modern `coli ui` on port 8790, which opens your browser. Keep both
terminals open while using it. The UI may open before model loading finishes.
When finished, stop each process with Ctrl+C in its own terminal. If either port
is already occupied, the shortcut refuses to start another instance and leaves
existing processes alone. To reopen just the UI while the server remains running:

```powershell
$install = "$env:LOCALAPPDATA\Colibri-PC-Setup\v2.1.0-vulkan"
& "$install\venv\Scripts\python.exe" "$install\app\coli" ui --host 127.0.0.1 --port 8790 --backend http://127.0.0.1:8000 --models-dir "$env:USERPROFILE\colibri-models"
```

**Colibri Serve Image** uses upstream `coli web` on port 8001 because that bundled
dashboard supports image generation. The modern `coli ui` at this release does
not have a working image-generation submission handler. No custom UI is added.
Stop the text server before using image generation; simultaneous memory use is
not validated. The installer creates no third UI shortcut and leaves existing
shortcuts alone. The modern UI Models page remains available for other downloads.

**Windows limitation:** upstream's UI model-switching service currently supports
Linux only. The Serve shortcut directly invokes the upstream CLI, so no custom model-selection interface is added. For a different downloaded model, use upstream's existing CLI in PowerShell:

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
- **RTX 3080 10 GB:** Qwen3.8-27B UD-Q4_K_M GGUF (about 16.6 GB), text-only, using Vulkan.
- **Two RTX 3060 12 GB:** Qwen3.8-Flash-Next IQ2_XS, Vulkan with `COLI_VK_DEV2=auto` enabling the
  upstream second-device tier. VRAM is not presented as one unified allocation.
  Upstream has not measured real multi-GPU Vulkan performance; verify both device
  names in engine output.
- **Intel Arc B580 12 GB:** Qwen3.8-27B UD-Q4_K_M GGUF (about 16.6 GB), text-only, using Vulkan, no CUDA overlay. Upstream chooses the preferred
  discrete device; verify the log identifies B580 rather than integrated graphics.

All profiles retain the installed GPU drivers. No CUDA toolkit or WSL is installed.
Pinned model artifacts are resumed and SHA-256 checked, including existing files.
Both text profiles import GGUF in link mode without duplicating or converting the
weight files. Model directories are under your configured `colibri-models`
folder. Preserve both the source and model subdirectories. Existing unrelated
models are not removed. Downloaded weights can be copied from another computer
into the corresponding source folder before rerunning setup; every artifact is
verified against the pinned manifest before import.
Do not infer performance from combined RAM/VRAM alone; actual inference on these
three PCs is not yet verified. The text models are text-only. The separate Qwen-Image-2.1 checkpoint is downloaded
for text-to-image generation on all three PCs, retaining its official directory
layout without conversion. It adds about 33 GB on disk. Image generation uses
Vulkan for supported operations with CPU work remaining; the image shortcut does
not enable the second-GPU text-model option. Its actual speed on these GPUs is
unverified. Video generation is not claimed.

Qwen-Image-2.1 uses the [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE).
Review its use restrictions before using generated images beyond permitted uses.
[Upstream image instructions](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/qwen-image.md).

Sources: [Windows release installation](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/windows.md),
[UI](https://github.com/JustVugg/colibri/blob/v2.1.0/ui/README.md),
[Vulkan devices](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/vulkan.md),
[desktop shell limits](https://github.com/JustVugg/colibri/blob/v2.1.0/desktop/README.md).
