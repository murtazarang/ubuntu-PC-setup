# Cleanup filesystem audit (2026-11-18)

Scope: filesystem discovery, process/service preflight, quarantine, purge and recovery in `Remove-LegacyAI.ps1`. This is not a claim that the real installed software was uninstalled or every machine state was tested.

## Source checks

- [Strata installer source](https://github.com/Niko1221/Strata/blob/c77572806996349b49995e4f98d41b5294d36a21/packaging/install.ps1): `STRATA_DATA_DIR` overrides `%LOCALAPPDATA%\Strata`; default terminal PATH is `Strata\terminal\current\bin`. The cleanup limits automatic inventory to its named local roots, reports custom locations and removes only the exact default PATH entry. Custom installs are not inferred to be owned.
- [Strata installation documentation](https://github.com/Niko1221/Strata/blob/c77572806996349b49995e4f98d41b5294d36a21/docs/INSTALL.md): chats/host state use `.strata` or `STRATA_HOME`; engine components use local app data. Chat/settings roots remain outside automatic cleanup.
- [XeStrata location source](https://github.com/MistVVK/XeStrata/blob/main/serve/places.py): Windows separates roaming settings and local data. The previous repository `Install-Model.ps1` additionally used `XeStrata-Setup` and GUID-named temporary archive directories. Inventory checks exact temporary-directory contents before accepting them.
- Historical quarantine finding (no longer used): [Move-Item, Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/move-item?view=powershell-5.1): `-LiteralPath` avoids wildcard interpretation; directory moves work only within one drive. This limitation motivated the earlier guard; direct removal no longer uses Move-Item or depends on same-drive destinations.
- [New-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item?view=powershell-5.1), [FileAttributes](https://learn.microsoft.com/en-us/dotnet/api/system.io.fileattributes): reparse-point flags identify linked roots and children. The direct-removal path does not create quarantine directories.
- [Get-ChildItem](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-childitem?view=powershell-5.1), [Remove-Item](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/remove-item?view=powershell-5.1): child enumeration uses `-Force`; only the narrowly verified upstream junction described below is handled. Direct deletion requires explicit DELETE confirmation. Prior quarantines are reported, never implicitly purged.
- [Win32_Process](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-process), [Win32_Service](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-service): preflight reads executable/command line/service path and blocks known references, rather than killing arbitrary Python or Node processes. ExecutablePath has privilege requirements. This is a best-effort snapshot, not proof that no process is using a file. The patch does not automatically change or stop services.

## Current direct-removal design (supersedes quarantine workflow)

The user explicitly rejected quarantine. Apply lists exact candidates and asks for `DELETE` before any uninstall, configuration mutation or permanent runtime deletion. It does not create a quarantine or move model files. Prior quarantines from older runs are reported but not automatically deleted.

Candidate roots and child links are checked before the first mutation. Strata's official installer source at `packaging/install.ps1:175–177` uses `mklink /J` for `terminal/current`. That exact junction is permitted only when its single absolute target is a non-linked descendant inside the same `terminal` directory. It is removed nonrecursively with [Directory.Delete](https://learn.microsoft.com/en-us/dotnet/api/system.io.directory.delete?view=netframework-4.8.1), then the owned root is deleted using `Remove-Item -LiteralPath -Recurse -Force -ErrorAction Stop`. Other links abort the preflight; targets are never independently added to inventory.

Settings files inside a runtime root, notably `Strata/app-settings.json`, and models inside that root are explicitly included in the confirmation. Separate roaming/chat directories and external/shared model libraries remain outside the automatic inventory. Relative configured paths are not resolved or advertised as definitely retained.

An error identifies the current possibly partially removed path and already removed roots. No rollback is promised, and rerunning inventories what remains. Windows filesystem deletion is not an atomic all-or-nothing transaction.

## Tests and limits

The isolated fixture suite passes on Linux PowerShell 7: dry-run and declined confirmation change nothing; confirmed removal deletes runtime only; rerun works; active-process and unexpected-link guards block deletion; a second-delete failure reports accurate partial state; recognized versus mixed temporary archives are scoped correctly. Windows 5.1/7 CI must additionally run the real internal junction fixture. No actual installed application, service, model or user data has been removed in these tests.

Process/service checks are best-effort snapshots; missing privileged metadata and file races remain possible. Path and link checks are not a race-proof security boundary against another concurrently modifying process. Running as a different account addresses that account's environment, not another user's install. No claims of exhaustive runtime success are made.
