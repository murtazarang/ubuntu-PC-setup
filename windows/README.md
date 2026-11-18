# Native Windows PC setup

**Current stack: Colibri inference + Open WebUI. New setup does not install or configure Oh My Pi.**
No WSL, Docker, disk formatting or HDD repartitioning is performed.

## Start without cloning the repository

Open **Windows PowerShell as administrator under the account being configured**, then run:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/run.ps1 | iex
```

This entry point is for a fresh installation. For an existing PC, use the [separate AI migration script](MIGRATE-AI.md); do not rerun the fresh Desktop stage to uninstall old AI software.

Choose your PC and stage. The launcher downloads its companion files and locates or installs PowerShell 7 automatically. It prints the retained setup folder for recovery.

| PC | Hardware argument | Assigned text model |
| --- | --- | --- |
| 5700G + RTX 3080 | `NvidiaSingle` | Qwen3.8-27B UD-Q4_K_M, about 16.6 GB |
| i5-13400 + Intel Arc B580 | `Intel` | Qwen3.8-27B UD-Q4_K_M, about 16.6 GB |
| 2700X + two RTX 3060s | `NvidiaDual` | Qwen3.8-Flash-Next IQ2_XS, about 68 GB |

1. **Drivers:** runs Windows Update and installs NVIDIA App or Intel Driver & Support Assistant. Open that vendor app, install its recommended graphics driver, then reboot. The script does not silently install a pinned GPU driver.
2. Run the same launcher again and choose **Desktop**. This installs applications, desktop/Firefox settings, Wikipedia, Colibri and Open WebUI. Downloads can take hours.

If using the retained setup folder directly, these are PowerShell 7 commands:

```powershell
./Setup.ps1 -Stage Drivers -Hardware NvidiaSingle
# After installing the vendor driver and rebooting:
./Setup.ps1 -Stage Desktop -Hardware NvidiaSingle
```

Substitute `NvidiaDual` or `Intel` as needed. The Desktop command also accepts `-ArchiveDirectory 'D:\YourFolder'`; the short interactive launcher does not expose that option.

## First use and daily controls

The setup supplies four daily-use shortcuts and one first-use setup shortcut:

- **Colibri Serve**: starts the assigned text model in the background on `127.0.0.1:8000`.
- **Colibri Serve Image**: starts Qwen-Image-2.1 in the background on `127.0.0.1:8001`.
- **Stop Colibri Model**: stops only model processes recorded and still recognized by this setup.
- **Open WebUI**: starts the local UI and Wikipedia bridge and opens the browser.
- **Finish Open WebUI Setup**: imports/verifies skills and connections and verifies Wikipedia integrity. It does not discover or remove old software.

No model terminal needs to stay open. Starting text or image stops the other setup-managed model; unrelated processes are not killed. A shortcut starting successfully does **not** mean model weights have finished loading. Logs are in `%LOCALAPPDATA%\OpenWebUI-PC-Setup` (`text.log`, `image.log`, `webui.log`). The Open WebUI model picker does not load or unload Colibri weights; use the Serve/Stop shortcuts.

Start a model, open **Open WebUI**, and create your local account. Then run **Finish Open WebUI Setup** and sign in when prompted. No password is embedded in the scripts. Alternatively, from PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\OpenWebUI-PC-Setup\Finish-OpenWebUI.ps1" -Root "$env:LOCALAPPDATA\OpenWebUI-PC-Setup"
```

The execution-policy argument is process-only, not a persistent policy change. The installer repairs its exact older Finish shortcut but preserves unrelated/custom shortcuts.

## Skills, Wikipedia and separate existing-PC migration

The three complete scientific, scientific-writer and education repositories provide **422 definitions / 3,968 original files**, including mirrored definitions. Their bytes and binary assets are imported through native Open WebUI APIs and read back; original repositories remain on disk. This does not install every optional executable tool or cloud service mentioned in the skills. A known cross-package relative reference is documented in [verification limits](../docs/openwebui-verification.md).

Offline Wikipedia uses OpenZIM MCP 3.4.0 through a separately installed mcpo 0.0.20 bridge, not OMP. The June 2026 English text-only archive is about 49 GiB. Interrupted HTTP downloads retain their partial file; rerun the same stage with the same archive directory. Completed archives are checked against the publisher's SHA-256. Copying a completed archive to the same expected filename in another PC's archive directory avoids redownloading once verification succeeds.

Fresh Desktop setup and **Finish Open WebUI Setup** install/configure only the new stack. They do not inspect or remove legacy OMP, Paseo or Strata installations. Existing local Wikipedia can be reused after checksum verification; routine integrity and non-overwrite safeguards still protect existing files.

For a PC with the old stack, use the [dedicated existing-PC migration](MIGRATE-AI.md):

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/migrate-ai.ps1 | iex
```

That separate workflow inventories/protects Wikipedia first, then asks for explicit confirmation of irreversible removal of the identified old stack, old skill collections and old-owned history/settings/caches **before installing the replacement**. Edits and custom files inside confirmed old roots are deleted, not compared against the new skills. Unknown/shared locations block cleanup rather than being silently skipped. Only after removal does it install the new AI stack and import/verify the new collections. Wikipedia and unrelated/new-stack data are preserved. There is no rollback if later installation fails. It does not run unrelated desktop/driver/Firefox setup. See [fresh first-use instructions](OPENWEBUI.md) for the separate fresh setup path.

## GPU and model behavior

Colibri keeps **Vulkan** on all three profiles. Dual RTX 3060 text inference sets `COLI_VK_DEV2=auto`; this is not a promise of unified VRAM or measured multi-GPU speed. Image inference does not enable that second-device text option. Check logs to confirm the intended GPU.

Open WebUI document-search models are separate from Colibri:

- NVIDIA: CUDA 12.8 PyTorch with native embedding/reranking inference checks.
- B580: explicit OpenVINO selection of the B580, with missing-GPU or CPU-inference errors instead of fallback. CPU PyTorch wheels there provide library/export utilities, not retrieval inference.
- Fresh retrieval defaults: `BAAI/bge-small-en-v1.5`, `cross-encoder/ms-marco-MiniLM-L6-v2`, BGE-token chunks 400/50, and the BGE model authors’ query-only prefix. Existing settings/indexes are not rewritten or automatically reindexed; conflicting settings stop verification.

Speech acceleration remains undecided. CUDA PyTorch does not prove Faster Whisper's separate cuBLAS/cuDNN requirements are satisfied. Native PDF extraction can flatten tables, lose equation/chart structure, and return no text for scans; no alternate OCR engine is silently selected.

All PCs also download the approximately 33 GB Qwen-Image-2.1 checkpoint for text-to-image generation. Video is not claimed. Its [Qwen Research License](https://huggingface.co/Qwen/Qwen-Image-2.1/blob/main/LICENSE) restricts permitted uses; retain and review the supplied license. Text GGUF imports use link mode: preserve both `source` and `model` subdirectories. Copied source weights are SHA-256 checked before import. Keep ample SSD headroom for Wikipedia, weights, dependencies and caches.

## Other desktop setup

Applications include Steam, Firefox, Stremio, Spotify, VS Code, PowerToys, Everything and SignalRGB. FanControl, Mailspring and ArtCraft are not installed by this Windows setup. Some installers have their own prompts. Steam uses native Windows graphics, not Proton.

PowerToys Run plus Everything targets Win+F2; clipboard history uses Win+V; PowerToys Awake is on demand. Existing Firefox/uBlock settings are protected. After the initial extensions load, close Firefox and run `./Configure-Firefox.ps1 -Release` from the retained folder in an elevated terminal to release the one-time managed filter-list values. Review its warnings about existing or other-user profiles; the Twitch resource URL remains managed.

## Verified coverage and remaining checks

[Exact Windows/Linux/protocol CI](https://github.com/murtazarang/ubuntu-PC-setup/actions/runs/44381356016) passed for `77db430` on November 18, 2026. It includes PowerShell 5.1/7 safe migration/shortcut fixtures, Linux tests, complete native skill import/readback/rerun, real Wikipedia fixture tool calls, real BGE/MiniLM **CPU test** retrieval, and a simulated Colibri image endpoint. The real Colibri release/UI staging smoke test is not the configured desktop UI workflow and does not prove model inference.

Full installation on the three PCs, actual CUDA/B580 inference, full-corpus searches, real image generation, Firefox GUI, desktop model switching and physical hardware behavior remain untested here. Verify those on the target PC. The local services use loopback ports only: text 8000, image 8001, Wikipedia 8002, Open WebUI 8080.

Sources: [Open WebUI integration and limitations](OPENWEBUI.md), [shared verification record](../docs/openwebui-verification.md), [Colibri Windows](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/windows.md), [Colibri Vulkan](https://github.com/JustVugg/colibri/blob/v2.1.0/docs/vulkan.md), [OpenZIM MCP](https://github.com/cameronrye/openzim-mcp), [PowerToys DSC](https://learn.microsoft.com/en-us/windows/powertoys/dsc-configure/microsoft-dsc).
