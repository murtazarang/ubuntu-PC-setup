# Existing Windows PC: replace only the AI stack

This is the **delete-old-first** migration requested for an existing PC. It does not run the fresh `Setup.ps1 -Stage Desktop` workflow.

Close old Strata/XeStrata/Paseo/OMP sessions. Open PowerShell as administrator under the existing user's account:

```powershell
irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/migrate-ai.ps1 | iex
```

Choose the PC when prompted. The launcher uses existing PowerShell 7, uv, Git and curl. It downloads companion scripts but runs only `Migrate-ExistingAI.ps1`. It does not run Windows Update, drivers, Firefox, PowerToys, unrelated applications or disk formatting.

## Order and irreversible removal

1. Inventory the old stack and configured skill roots. Protect the existing/default Wikipedia archive location and any existing replacement Colibri/WebUI models/data. Linked paths, overlap with protected data, and unknown/shared custom locations stop the migration before deletion rather than being guessed disposable.
2. Uninstall Paseo and delete the explicitly listed old Strata/XeStrata runtime/download directories. Confirm their permanent deletion when asked.
3. Delete identified old skill collections and app data, **including modifications, custom additions, histories, settings and caches inside those listed roots**. Each directory requires typing its exact full path. The three old `%LOCALAPPDATA%\OMP-Skills` collection directories are individually removed, not their parent containing unrelated siblings. Source-owned default data roots include `%USERPROFILE%\.omp`, `%USERPROFILE%\.paseo`, and `%APPDATA%\Paseo`, `Strata`, and `xestrata`. No quarantine is created.
4. Remove the identified OMP program installation through the supported binary/Bun/npm path and verify executable absence. Node/Bun themselves and other packages remain.
5. Install the replacement Colibri/Open WebUI stack, download/import its models and complete new skill collections, and verify GPU support. Retained verified artifacts and Wikipedia are reused.
6. Open WebUI without switching or starting a model. Create its local account, then return to the terminal for authenticated skill/connection/corpus verification. Use the new model shortcuts afterward.

**If replacement installation fails, the old software may already be gone.** This is deliberately not a transactional migration or rollback. Wikipedia and unrelated/new-stack data remain; rerun this AI-only migration to continue. Declining a deletion reports incomplete cleanup, not success.

Nondefault app-data overrides and skill roots outside known owned directories are printed as blockers for ownership review. They are not silently retained while claiming a complete cleanup, and shared/foreign directories are not recursively deleted based only on an OMP reference. All stored default/named OMP profile YAML/JSON configurations are parsed read-only, including when the old CLI is absent. The parser uses uv and PyYAML as an inventory utility, not a new AI-stack installation. Nondefault external overlays are explicit ownership-review blockers.

Recovery files remain under `%LOCALAPPDATA%\PC-Setup\AI-Migration`. Fresh **Finish Open WebUI Setup** only finishes imports/configuration and never performs old-stack cleanup.

The migration does not start or switch text/image model servers; after installation, use the separate model shortcuts.

## Verification boundary

Safe fixtures execute the bounded migration stages with inert helper files and confirm destructive-first order, cancellation blocking later stages, active model/corpus protection, and later setup failure propagation. Separate disposable-directory tests cover deletion of modified old collections/app data with exact-path confirmation while preserving Wikipedia and unrelated siblings. Full native uninstallers, GPU inference and complete device migration still require the Windows PC.

Source path definitions: OMP `packages/utils/src/dirs.ts`; Paseo `server/src/server/paseo-home.ts` and `desktop/src/main.ts`; Strata `discovery.py`/`paths.py`; XeStrata `serve/places.py`. The original setup's `Install-Skills.ps1` defines the three old collection destinations.

Migration also refuses cleanup if an unregistered `.zim` archive or `.zim.part` download is found inside an old deletion root. It prints the path and leaves it untouched; relocate the corpus deliberately and configure its retained location before retrying. It does not silently move or delete an archive.
