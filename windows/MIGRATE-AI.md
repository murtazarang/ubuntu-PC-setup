# Existing Windows PC: replace only the AI stack

Do **not** rerun `Setup.ps1 -Stage Desktop` for this migration. Fresh setup and existing-PC migration are separate workflows.

Close old Strata/XeStrata/Paseo/OMP sessions first. Open PowerShell as administrator under the existing user's account and run:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/migrate-ai.ps1 | iex
```

Choose your PC when prompted. This launcher uses the already-installed PowerShell 7, uv, Git and curl. Missing prerequisites cause a specific error rather than running unrelated installers. The full repository ZIP is downloaded for companion files, but only `Migrate-ExistingAI.ps1` runs.

The migration:
1. Reuses the existing OpenZIM reference manifest's archive location and verifies the corpus checksum. Without a manifest it uses the original default archive directory. Pass `-ArchiveDirectory` to the downloaded `Migrate-ExistingAI.ps1` if you moved the corpus.
2. Provisions Colibri and Open WebUI and their supporting GPU models/complete skill collections. Existing verified model artifacts are reused.
3. Starts WebUI and the Wikipedia bridge only; it does not start or switch text/image model servers. Create your local account in the browser on first launch, then return to the terminal. No cloud account is created.
4. Imports and reads back the complete skill packages, verifies the persisted connections/retrieval settings and rechecks Wikipedia. Failure stops before uninstalling anything.
5. Checks that no active corpus, replacement model directory, WebUI data/skills, or preserved OMP skill/config root overlaps a proposed legacy deletion.
6. Runs the existing exact-confirmation Paseo/Strata/XeStrata cleanup, then confirmed OMP program removal. Declining cleanup means migration is incomplete, not success. Retired OMP configuration is preserved rather than edited through its old CLI.

It does not run Windows Update, GPU-driver setup, Firefox, PowerToys, other desktop application installers, or disk formatting. Existing accounts/chat/settings, custom skills, separate model libraries and Wikipedia remain. Displayed legacy runtime directories can contain old model files: the permanent-deletion confirmation explicitly covers those paths, so read it before agreeing.

Use the new **Colibri Serve**, **Colibri Serve Image**, **Stop Colibri Model** and **Open WebUI** shortcuts afterward. Fresh **Finish Open WebUI Setup** only finishes imports/configuration and never removes old software. Cleanup belongs to the separate migration command.

Migration files are retained under `%LOCALAPPDATA%\PC-Setup\AI-Migration` after an error. Rerun the AI migration, not the full desktop setup. The migration refuses unknown installations or live ownership rather than guessing which processes/files to remove.

## Verification limits

Safe fixtures exercise the actual bounded orchestration stages with inert helper files: failed import blocks all removal; declined legacy removal blocks OMP removal; successful order is verification, legacy cleanup, then OMP; overlapping active data paths are rejected. Real target GPU inference, native application uninstallers and the complete migration still require the Windows PC.
