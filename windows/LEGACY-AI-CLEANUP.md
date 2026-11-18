# Remove the former Paseo / Strata / XeStrata setup

This Windows-only patch is separate from the Colibri installer. It does not uninstall
GPU drivers, shared Python/uv/Git packages, Oh My Pi, skills, OpenZIM or Wikipedia.
It does not delete Colibri or infer that existing shared models belong to this setup.
Run it as the Windows user whose previous setup you want to remove. Close Paseo
and the old inference servers first. It refuses active processes/services rather
than killing unrelated Python or Node processes.

In PowerShell:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/remove-legacy-ai.ps1 | iex
```

The launcher opens Paseo's registered uninstaller; leave any chat/user-data removal
option unchecked. It moves the dedicated old Strata/XeStrata runtime trees and
recognized leftover installer downloads into a recovery folder. It then asks you
to type `DELETE` if you want to **permanently delete that run's quarantine** and
free its disk space. Anything else retains the quarantine. External/custom model
libraries are reported, not deleted, because the previous software can reuse files
that were not downloaded by this setup. There is no reliable historical manifest
proving ownership of those external files.

For inventory only, run `Remove-LegacyAI.ps1` without switches from a checkout.
`-Apply` uninstalls/quarantines; `-Apply -PurgeQuarantine` also prompts for permanent
removal. The default inventory does not modify anything.

Known destinations:
- `%LOCALAPPDATA%\Strata` (including its own components/model files)
- `%LOCALAPPDATA%\XeStrata-Setup`
- `%LOCALAPPDATA%\xestrata`
- `%TEMP%\strata-install.ps1`
- `%TEMP%\UbuntuPCSetup-Windows\Paseo-Setup-0.16.0-beta.2-x64.exe`
- Recognized `%TEMP%\xestrata-<GUID>` archive-only leftovers

Custom `STRATA_*`/`PASEO_HOME`, Strata/XeStrata saved data-folder references, and
`Documents\Strata` are printed for review. Shared Hugging Face caches are retained.
The default Strata terminal PATH entry is removed; other PATH entries are preserved.
Paseo chat state (`.paseo`), Strata chats (`.strata`) and roaming app settings are
retained. A customized/unrecognized Paseo uninstall command requires using Windows
Settings instead of executing arbitrary command text.

The exact former setup-generated OMP `local-inference` provider and its global
model roles are removed if they match; unrelated/customized providers and project
settings remain. This step uses the existing OMP and uv commands. If either is
unavailable, the script warns that settings are retained. Configuration backups
are kept in `%LOCALAPPDATA%\PC-Setup\LegacyAI-Config-Backup`, outside the purge.

Recovery manifests are in `%LOCALAPPDATA%\PC-Setup\LegacyAI-Quarantine\<run>\manifest.json`.
Each record maps the original path to its quarantine destination. A `planned`
record can mean the move was interrupted: inspect both locations before restoring.
No automatically scheduled task or background deletion is created. Partial failure
is reported; a stopped cleanup must not be interpreted as a complete uninstall.
