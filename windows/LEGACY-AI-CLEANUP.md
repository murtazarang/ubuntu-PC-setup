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

The launcher applies cleanup, but first shows the exact discovered paths and asks
you to type `DELETE` before permanently removing their contents. This includes
any models and local settings stored inside the listed Strata/XeStrata directories.
Declining the confirmation leaves those files in place. There is no new quarantine
or delayed purge stage. Paseo is removed through its registered native uninstaller;
the patch does not add its user-data-deletion flag.

For inventory only, run `Remove-LegacyAI.ps1` without switches from a checkout.
`-Apply` performs the confirmed uninstall and direct removal. The default inventory
does not modify anything. Unknown/shared external model libraries are reported,
not assumed to belong to this setup.

Known destinations:
- `%LOCALAPPDATA%\Strata` (including its own components/model files)
- `%LOCALAPPDATA%\XeStrata-Setup`
- `%LOCALAPPDATA%\xestrata`
- `%TEMP%\strata-install.ps1`
- `%TEMP%\UbuntuPCSetup-Windows\Paseo-Setup-0.16.0-beta.2-x64.exe`
- Recognized `%TEMP%\xestrata-<GUID>` archive-only leftovers

Custom `STRATA_*`/`PASEO_HOME`, Strata/XeStrata saved data-folder references, and
`Documents\Strata` are printed for review. A reference inside a listed deletion root
is included in removal; external/shared locations are retained. The local
`Strata\app-settings.json` is part of the Strata root, not separately retained.
Shared Hugging Face caches are retained.
The default Strata terminal PATH entry is removed; other PATH entries are preserved.
Paseo chat state (`.paseo`), Strata chats (`.strata`) and roaming app settings are
retained. A customized/unrecognized Paseo uninstall command requires using Windows
Settings instead of executing arbitrary command text.

The exact former setup-generated OMP `local-inference` provider and its global
model roles are removed if they match; unrelated/customized providers and project
settings remain. This step uses the existing OMP and uv commands. If either is
unavailable, the script warns that settings are retained. Configuration backups
are kept in `%LOCALAPPDATA%\PC-Setup\LegacyAI-Config-Backup`, outside the runtime deletion paths.

Any quarantine left by an earlier version is reported and preserved, not silently
purged. If removal fails, the script identifies the completed and remaining paths;
read that output before rerunning. Direct removal is not reversible and is not an
atomic transaction. No scheduled or background deletion is created.

### Registered Paseo uninstall arguments

Paseo v0.16.0-beta.2 uses electron-builder 26.18.0's interactive NSIS installer.
That upstream writes an `UninstallString` containing the executable followed by
`/currentuser` or `/allusers`. The cleanup preserves that registered scope and
passes it as an argument to `Start-Process`; it does not evaluate the registry
string as shell code. Bare executable entries remain supported. Unknown options,
compound commands and silent/data-deletion options are rejected rather than guessed.
The patch does not add `/S` or `--delete-app-data`.

Sources:
- [Paseo packaging configuration](https://github.com/getpaseo/paseo/blob/v0.16.0-beta.2/packages/desktop/electron-builder.yml)
- [Exact electron-builder NSIS registry command construction](https://unpkg.com/app-builder-lib@26.18.0/templates/nsis/include/installer.nsh)
- [NSIS uninstaller data-retention behavior](https://unpkg.com/app-builder-lib@26.18.0/templates/nsis/uninstaller.nsh)
- [PowerShell Start-Process arguments](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process)

Tests cover the reported quoted path with spaces and `/currentuser`, `/allusers`,
bare commands, rejection of extra commands/options, and execution of a harmless
compiled Windows EXE to verify real argument delivery. They do not uninstall a
real Paseo installation.
