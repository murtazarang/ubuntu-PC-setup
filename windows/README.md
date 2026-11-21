# Native Windows PC setup

**Current text stack: native Hermes Agent + llama.cpp.**
No WSL, Docker, disk formatting or HDD repartitioning is performed.

## Start without cloning the repository

Open **Windows PowerShell as administrator under the account being configured**, then run:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/run.ps1 | iex
```

This entry point is for a fresh installation. For an existing PC, use the [separate AI migration script](MIGRATE-AI.md); do not rerun the fresh Desktop stage to uninstall old AI software.

Choose your PC and stage. The launcher downloads its companion files and locates or installs PowerShell 7 automatically. It prints the retained setup folder for recovery.

| PC | Hardware argument | Text model and context |
| --- | --- | --- |
| RTX 3080 | `NvidiaSingle` | Nemotron 3.5 Bolt 74B, CUDA, 128K |
| Intel Arc B580 | `Intel` | Nemotron 3.5 Bolt 74B, Vulkan, 128K |
| Two RTX 3060s | `NvidiaDual` | Qwen3.8 Flash-Next GSQ-RCO Q2_0, CUDA layer split, 256K |

1. **Drivers:** runs Windows Update and installs NVIDIA App or Intel Driver & Support Assistant. Install the recommended driver in the vendor app, then reboot.
2. Run the same launcher again and choose **Desktop**. It installs the applications, desktop/Firefox settings, local AI, and Wikipedia. Downloads can take hours.

From the retained setup folder in PowerShell 7:

```powershell
./Setup.ps1 -Stage Drivers -Hardware NvidiaSingle
# After installing the recommended driver and rebooting:
./Setup.ps1 -Stage Desktop -Hardware NvidiaSingle
```

Substitute `NvidiaDual` or `Intel` as needed. Desktop accepts `-ArchiveDirectory 'D:\YourFolder'` to reuse a verified archive or resume a partial.

Click **Start Local AI** to start the model and open the official Hermes Webapp; click **Stop Local AI** to release model memory. No second web front end or cloud account is required. The writing and education skills and the offline Wikipedia search tool are available in Hermes. See [Local AI setup](../docs/hermes-local-ai.md) for use, source pins and verification limits.

On an existing PC use the [separate migration](MIGRATE-AI.md), not the fresh Desktop stage. Existing image-generation software is not converted as part of this text migration.

## Other desktop setup

Applications include Steam, Firefox, Stremio, Spotify, VS Code, PowerToys, Everything and SignalRGB. FanControl, Mailspring and ArtCraft are not installed by this Windows setup. Some installers have their own prompts. Steam uses native Windows graphics, not Proton.

PowerToys Run plus Everything targets Win+F2; clipboard history uses Win+V; PowerToys Awake is on demand. Existing Firefox/uBlock settings are protected. After the initial extensions load, close Firefox and run `./Configure-Firefox.ps1 -Release` from the retained folder in an elevated terminal to release the one-time managed filter-list values. Review its warnings about existing or other-user profiles; the Twitch resource URL remains managed.

## Verification

See [Local AI setup](../docs/hermes-local-ai.md#verification) for what is checked and what has not been measured on physical hardware. The separately maintained AX206 display scripts are not changed by AI setup or migration.
