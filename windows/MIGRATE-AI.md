# Existing Windows PC: migrate local text AI

Use this AI-only path on an existing PC. A clean Windows install uses the separate desktop installer and does not perform legacy cleanup. Close old Strata, XeStrata, Paseo and OMP sessions before starting. In PowerShell as administrator under the existing user's account:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/migrate-ai.ps1 | iex
```

Choose the hardware profile when prompted. The launcher uses existing PowerShell 7, uv, Git and curl, fetches the companion scripts and invokes `Migrate-ExistingAI.ps1`. It does not run Windows Update, reinstall drivers or desktop apps, modify Firefox or format disks.

## What happens

1. Check the existing Wikipedia manifest, if present, and pass its archive directory to the new installer. A conflicting explicit path, malformed/linked manifest, or a cleanup target overlapping protected data stops the migration. A known unregistered `.zim` or `.zim.part` inside a deletion root also stops cleanup so it can be relocated deliberately. The archive and partial download are not moved or deleted; the reference installer verifies the complete archive or resumes the same partial.
2. Inventory the legacy runtime/download directories, old skill roots, and OMP install. On explicit confirmation, uninstall Paseo, remove the listed Strata/XeStrata runtime/download directories, then remove confirmed old skill/app data and the identified OMP install. Directory confirmation covers all contents inside the listed root, including modifications, settings and history; these deletions are permanent. Unknown/shared paths are not automatically deleted. Node, Bun, shared packages, outside cache directories, and unrelated apps are not removed.
3. Install managed Hermes, the approved llama.cpp profile and model, and the staged scientific/writer/education skills. Set up the local OpenZIM connection and **Start Local AI** / **Stop Local AI** shortcuts. The migration does not start or switch text/image model servers.
4. After the new installation succeeds, an optional `RETIRE TEXT` prompt can archive the matching setup-owned **Colibri Serve** text shortcut and stop its recorded text server. It leaves the **Colibri Serve Image** and **Stop Colibri Model** shortcuts and the existing **Open WebUI** image front end, its data and bridge intact. It does not delete Colibri files or model weights. Do not run the old Colibri image stack and the new text stack together if they compete for the same GPU; stop the workload you are not using.

**If replacement installation fails, the older OMP/Paseo/Strata stack may already be gone.** This is not a rollback-capable migration. The Colibri/Open WebUI image workflow, Wikipedia, and unrelated data are not uninstall targets. Rerun the AI-only migration after addressing the actual error. Declining a required legacy deletion stops migration; declining optional text retirement keeps the old text launcher.

Download staging remains under `%LOCALAPPDATA%\PC-Setup\AI-Migration`. The ordinary **Start Local AI** shortcut runs Hermes and the configured llama.cpp server; opening **Stop Local AI** stops the managed text workload. Existing Open WebUI chat history, indexes and settings are not imported into Hermes.

## Verification boundary

Migration fixtures use inert helpers and disposable directories for ordering, decline handling, corpus and model-path protection, and installation failure handling. They do not run real uninstallers, download the full corpus or model, or test GPU output on these PCs. On the actual PC, open a native Hermes skill and check a real offline Wikipedia tool result before retiring old text launchers; the new launcher is independent of the preserved image workflow.
