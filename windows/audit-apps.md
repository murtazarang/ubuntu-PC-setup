# Independent command audit: applications, desktop, Firefox, Everything

Audit date: 2026-11-14. This ledger describes the files as read during this review, before subsequent fixes. It is **not a Windows execution certificate**. No installers, services, registry writes, or browser policies were executed. Line ranges refer to the reviewed copies. `V` means the named upstream interface/argument was checked, `I` means code inspected only, `U` means unresolved behavior or missing direct verification. A row can have both V and U: valid syntax does not establish successful installation.

## Findings requiring disposition

1. **Installer wait can appear hung (Install-Apps.ps1:44).** Microsoft documents `Start-Process -Wait` waits for the descendant process tree, not merely the installer. Paseo's electron-builder configuration is assisted NSIS (`oneClick:false`) and does not disable `runAfterFinish`; electron-builder defaults that to true. Completing the installer with its launch checkbox selected can therefore keep setup waiting for the launched app. Explain this explicitly before launch and verify on Windows, or use a documented installer mechanism to suppress launch. Do not replace this with an arbitrary sleep. This is a source-supported risk, not a reproduced Paseo hang.
2. **Existing custom install locations are not adequately resolved.** Configure-Desktop.ps1:10–15 recognizes two PowerToys locations; Install-Everything.ps1:22–24 recognizes PATH or Program Files. An already-installed custom-location app is skipped by `--no-upgrade` then potentially reported missing. Resolve registered install locations/executables; retain validation. Both products allow installation choices. Existing 32-bit Everything on x64 can also be under Program Files (x86).
3. **Preservation boundary is narrower than Firefox policy scope.** apply_firefox_policy.py checks only the current account's profiles.ini, but writes an installation-wide Firefox policy. Another account's pre-existing uBO configuration can receive `toOverwrite` despite the current-user safeguard. Custom profiles absent from profiles.ini are also outside that safeguard. Either avoid destructive initialization by default or explicitly constrain/document and test the affected profile scope. This is inferred from code and Mozilla's installation-wide policy design.
4. **Direct installer exit/registration contracts remain unverified.** FanControl/SignalRGB/ArtCraft regex matching and zero-only exit handling have not been proven from their exact installers. The SignalRGB WinGet manifest confirms its user-local VortxEngine product registration, but does not establish the DisplayName regex. Do not label those checks validated until the exact registration and success/reboot/cancel codes are examined or exercised safely on a disposable Windows machine.
5. **Rerun does not repair a broken registered install.** Test-DirectAppInstalled treats DisplayName registration as sufficient; it never verifies executable presence. This is a conservative preservation policy, not installation health verification. Report skip distinctly from verified working.
6. **PowerToys settings assumptions need version-specific runtime coverage.** JSON property names have upstream support, but missing launcher settings are synthesized, then plugin loading is left to the next app start. Neither the resulting Win+F2 operation nor plugin loading has been exercised here. Also the comment claiming PowerLauncher is not a DSC resource is stale against current Microsoft documentation, which now lists PowerLauncherSettings. That does not itself invalidate the JSON implementation.
7. **Current-user versus alternate-admin context is consequential.** HKCU, APPDATA, LOCALAPPDATA and Store app queries refer to the executing account. Elevating with different credentials configures that admin, not necessarily the intended desktop user. The orchestration must enforce/communicate same-user elevation or pass an explicitly resolved target context. No claim of correct alternate-credential operation is made.

## Source register

- W: https://learn.microsoft.com/en-us/windows/package-manager/winget/install (all WinGet switches below).
- P: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process (FilePath, ArgumentList, Wait, PassThru, environment inheritance and process-tree wait).
- U: https://docs.astral.sh/uv/reference/cli/ (`run`, `--no-project`; Python selection/download remains host-dependent).
- E: https://www.voidtools.com/support/everything/command_line_options/ (service/startup switches).
- EP: https://github.com/lin-ycv/EverythingPowerToys/wiki (supported installation instructions).
- EPS: https://github.com/lin-ycv/EverythingPowerToys/blob/main/NSIS/exeCreator.nsi (user-local destination, installation registry, error handling).
- EPM: https://github.com/lin-ycv/EverythingPowerToys/blob/main/plugin.json (ID, name, DLL, global default).
- PT: https://github.com/microsoft/PowerToys/blob/main/src/modules/launcher/Microsoft.Launcher/dllmain.cpp (open_powerlauncher keys).
- PTR: https://github.com/microsoft/PowerToys/blob/main/src/runner/main.cpp (general enabled settings).
- PTD: https://learn.microsoft.com/en-us/windows/powertoys/dsc-configure/microsoft-dsc (current resource list; stale comment noted).
- F: https://firefox-admin-docs.mozilla.org/reference/policies/extensionsettings/ (normal_installed and install_url).
- F3: https://firefox-admin-docs.mozilla.org/reference/policies/3rdparty/ (managed extension settings).
- FP: https://mozilla.github.io/policy-templates/ (legacy installation-path guidance; site explicitly redirects current policy documentation to firefox-admin-docs).
- B: https://github.com/gorhill/uBlock/blob/master/src/js/storage.js (managed settings restoration / overwrite semantics), https://github.com/gorhill/uBlock/blob/master/assets/assets.json (list IDs).
- EB: https://www.electron.build/docs/api/app-builder-lib.interface.nsisoptions/ (runAfterFinish defaults).
- PA: https://github.com/getpaseo/paseo/blob/v0.16.0-beta.2/packages/desktop/electron-builder.yml (exact-tag availability not independently established in this pass; corresponding local upstream source inspected).
- AMO: https://addons.mozilla.org/api/v5/addons/addon/ublock-origin/ , https://addons.mozilla.org/api/v5/addons/addon/7tv-new/ , https://addons.mozilla.org/api/v5/addons/addon/ttv-lol-pro/ (queried successfully; all three configured GUIDs agree).
- WM: https://github.com/microsoft/winget-pkgs/tree/master/manifests (package-directory checks and specific manifests described below; Microsoft-maintained community manifests, not a promise from each application vendor).

## PowerShell command and argument ledger

Repeated command forms are covered together; this does not omit their failure paths. Language statements, assignments, comments and data literals are covered in the relevant range. **Generic cmdlet arguments marked I have not yet each been independently compared with their own Microsoft reference page. This audit must not be represented as completing that requested stronger condition.**

| File:lines | Command / arguments / defaults | Status and behavior reviewed |
|---|---|---|
| All PS files:2–5 | CmdletBinding, param, Set-StrictMode -Version Latest, ErrorActionPreference Stop | I. Native executable nonzero codes still require explicit checking; checked at call sites. Latest strict behavior can change with runtime. |
| Apps:6–8 | Get-Command winget.exe -ErrorAction SilentlyContinue | I. Checks resolution, not executable health or exact source. Missing throws before app mutation. |
| Apps:11,71; Everything:11 | winget install --exact --id ID --source winget/msstore --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade | V W. Every listed flag exists. --no-upgrade preserves existing version; --disable-interactivity is not an explicit silent installer request. Scope, architecture, installer selection and interactive installer behavior depend on manifests/preferences. U on actual host. |
| Apps:12–14,72–74; Everything:12–13 | LASTEXITCODE -> unsigned 8-digit hex; accepts 0, 8A150061, 8A15010D | I. Format masks signed native results correctly by inspection. Exact HRESULT meanings not reverified against winget source in this pass. U until mapped from current Result.h. |
| Apps:16–27,50–59 | Get-ItemProperty -Path HKCU/HKLM/WOW6432Node Uninstall wildcard -ErrorAction SilentlyContinue; PSObject.Properties; regex | I. Covers regular current-user and machine registrations, not other users or portable copies. Swallows registry errors as missing; no executable validation. Regex contracts U for direct apps. |
| Apps:34–38 | Join-Path TEMP, New-Item -ItemType Directory -Force -Path, Out-Null, Invoke-WebRequest -Uri -OutFile | I. Stable temp filename; reruns replace partial download, no resume. No retry or explicit timeout. Generic cmdlet docs not individually checked. |
| Apps:39–41 | Get-FileHash -LiteralPath -Algorithm SHA256; compare expected | I. Applied only to Paseo. Exact release digest has not been independently re-downloaded in this pass. |
| Apps:44–48 | Start-Process -FilePath -Wait -PassThru; ExitCode !=0; registry postcheck | V P for arguments; U for each installer exit contract. Process-tree waiting risk above; no automatic account creation. |
| Apps:59 | Test-Path -LiteralPath APPDATA/Spotify/Spotify.exe | I. User-local Win32 Spotify fallback; doesn't prove binary functional. |
| Apps:62–66 | built-in powershell.exe -NoProfile -NonInteractive -Command; Get-AppxPackage -Name SpotifyAB.SpotifyMusic; exit 0/1/2 | I/U. Explicit Windows PS host avoids Appx compatibility assumptions. Current-user scope and Store install under elevated session not executed. Exact package identity not independently queried here. |
| Apps:77–83 | eleven package IDs; foreach Install-WingetApp | See package ledger. No package health probe beyond exit status. |
| Apps:86,88–89 | Run-Installer URI, filename, optional hash, -DisplayNamePattern | I/U. User URLs retained; downloaded bytes and exact installer success behavior not tested. |
| Apps:91–98 | Invoke-RestMethod GitHub releases/latest; assets regex; require exactly one; Run-Installer | I/U. Fails safely on no/multiple assets. Latest non-prerelease endpoint documented semantics not independently checked this pass. ArtCraft exact release schema/registration remains U. |
| Desktop:6–8 | New-Item HKCU Clipboard -Force; New-ItemProperty EnableClipboardHistory -Value 1 -PropertyType DWord -Force | I/U. Value chosen matches intended feature but Microsoft policy versus preference semantics were not independently verified in this pass. Not runtime tested. |
| Desktop:10–21 | Join-Path candidates; Where-Object Test-Path -LiteralPath; Select-Object -First 1; Start-Process runner; Read-Host | I; P for launch. Custom-location omission and same-account assumption. First launch is explicitly manual. |
| Desktop:22–27; Everything:7–9 | Get-Process -Name PowerToys,PowerToys.Settings -ErrorAction SilentlyContinue; prompt/refuse | I. No process killed. Name list does not independently prove all settings-writing child processes are gone. |
| Desktop:30–32; Everything:18–20; Firefox:6,20–23 | Get-Command uv.exe -CommandType Application -ErrorAction Stop; & uv run --no-project python helper arguments; LASTEXITCODE | V U for uv flag; I for PowerShell construction. Paths passed as separate arguments, not joined shell strings. Python may be selected/downloaded by uv; no specific Python version enforced. |
| Desktop:33–36 | call Install-Everything.ps1; Start-Process runner; Write-Host | I; P. No readiness check after relaunch. Awake is enabled but duration intentionally left to user. |
| Everything:15–17 | Join-Path plugin folder; Test-Path manifest | V EPS for path. Checks file exists, not plugin compatibility with actual PT version. |
| Everything:22–24 | Get-Command Everything.exe -CommandType Application -ErrorAction SilentlyContinue; fallback ProgramFiles; Test-Path | I. Custom install/x86 fallback omission. |
| Everything:27–31 | Get-Service -Name Everything; Start-Process -ArgumentList '-install-service' -Wait -PassThru; Start-Service -Name Everything -ErrorAction Stop | V E/P for installation option and process invocation. E says install-service starts service and needs admin. Start-Service is redundant if already started but normal by design. Exact service health/runtime untested. |
| Everything:32–34 | Start-Process -ArgumentList '-install-run-on-system-startup' -Wait -PassThru; '-startup' | V E/P. First registers current-user startup; latter starts background without search window. Options return immediately rather than showing search UI. Exit success semantics not exercised. |
| Firefox:9–18 | registry App Paths Get-ItemProperty defaults plus ProgramFiles/x86/LocalAppData; first Test-Path | I. Better location discovery than desktop. First existing install wins when multiple editions exist; intended edition not proven. |
| Firefox:19–26 | policies.json by executable; uv helper --profiles path; optional --release | V FP/F3 for policy placement/use; I helper flags. Release is a separate manual step; no proof initial addon launch applied settings before release. |

## Package/default selection ledger

All eleven package directory paths exist in Microsoft's manifest repository. Directory existence validates spelling, **not current installability**. Scope and modes below are from explicitly fetched installer manifests; other package defaults remain U.

| ID | Inspection | Remaining unknown |
|---|---|---|
| Git.Git | V directory manifests/g/Git/Git | Selected architecture/scope/installer and new PATH availability not verified here. |
| astral-sh.uv | V directory manifests/a/astral-sh/uv | Selected manifest and executable alias availability not verified here. |
| Mozilla.Firefox | V directory manifests/m/Mozilla/Firefox | Locale/scope/Store versus Win32 existing-install interactions U. |
| Valve.Steam | V 2.10.91.91 manifest: machine, NSIS, x86 installer, self-elevation, official Steam CDN | Actual client self-update/login/game compatibility not tested. |
| Stremio.Stremio | V 4.4.181: user, NSIS, x86, silent modes, official dl.strem.io | Fresh-session install behavior not tested. |
| Foundry376.Mailspring | V 1.26.2: user, exe, --silent manifest switches, official GitHub release | Account requirements and launched process behavior U. |
| Microsoft.VisualStudioCode | V directory | User/system installer selection U. |
| Microsoft.PowerToys | V directory, upstream runner/settings source | Chosen version/location and plugin version compatibility U. |
| 7zip.7zip | V directory | Selected installer/scope U. |
| Microsoft.DotNet.DesktopRuntime.10 | V directory | Selected patch, reboot semantics U. |
| Microsoft.VCRedist.2015+.x64 | V directory | Selected patch, reboot semantics U. |
| voidtools.Everything | V 1.4.1.1032 manifest: x64 MSI, NSIS and portable choices; official voidtools URLs | Omitting installer-type leaves choice to resolver/preferences; portable/custom install needs more discovery. |
| lin-ycv.EverythingPowerToys | V 0.91.1: user NSIS, /S silent, documented exact destination and PT dependency | Compatibility with retained old PowerToys U; --no-upgrade preserves old plugin too. |
| Spotify Store 9NCBCSZSJRSB | I code | Exact Store availability, account policy, elevated install behavior U. |
| Paseo v0.16.0-beta.2 | I local upstream builder config; V electron-builder defaults | Exact tag/hash and actual installer registration/process tree U. |
| FanControl V285 net4.8 | User's URI preserved | Binary/registration/exit behavior U. |
| SignalRGB | V WM 2.5.86 confirms exact URL, exe, --silent, ProductCode VortxEngine, LocalAppData/VortxEngine | DisplayName regex and actual binary exits U. |
| ArtCraft | I latest asset selector | Exact current Windows asset and installer behavior U in this pass. |

## Python helper line/argument coverage

Python's json/pathlib/tempfile/os/shutil/subprocess/argparse interfaces below were inspected in code; their standard-library reference pages were not individually reopened. Thus I is intentional, not implicit V.

| File:lines | Operations / data arguments | Status / findings |
|---|---|---|
| configure_powertoys.py:16–32 | deepcopy; dict validation; enabled PowerToys Run/Awake; open_powerlauncher win/alt/ctrl/shift/code=113 | V PT/PTR for property structure; I numeric F2 assignment; U actual hotkey capture/conflicts. Existing unrelated values preserved. |
| configure_powertoys.py:35–49 | backup only if absent, tempfile same parent, json.dump, os.replace, cleanup | I. Atomic single-file replacement, first backup retained. File permissions/ACL preservation not verified. |
| configure_powertoys.py:52–67 | required general settings, optional launcher {}; sequential saves; argparse directory | I. Two-file operation not transactional; second failure leaves first changed. Rerun can converge but not all-or-nothing. |
| configure_everything.py:8–27 | fixed plugin ID; deepcopy; plugins list and entries; case-normalized Id; duplicate rejection; Disabled=False | V EPM for ID; I behavior. Existing IsGlobal preference preserved, potentially no global results if user disabled it. New entry intentionally omitted so PT defaults apply. |
| configure_everything.py:30–50 | utf-8-sig JSON; manifest Name/ID; DLL basename/existence; settings load/save; required --settings/--manifest | V EPM fields and DLL. I safe failure on malformed files. Does not load DLL, compare API versions or test querying. |
| apply_firefox_policy.py:13–34 | ConfigParser profiles; relative/absolute paths; extensions.json + XPI existence; GUID | V AMO GUID. I current-user preservation detection. Multi-user/custom-profile omission above. |
| apply_firefox_policy.py:37–48 | read old policies; refuse pre-existing uBO with no managed policy; call policy helper | I. Preserves unrelated policy but purposely blocks an existing-profile setup rather than migrating filters. |
| apply_firefox_policy.py:49–69 | subprocess.run current executable/capture; check return; tempfile + os.replace; argparse path/--profiles/--release | I. No backup of existing policy; merge preserves keys by inspection. Windows file locking/ACL untested. |
| firefox-policy.py:4–13 | --release only; policies/ExtensionSettings objects; addon mode normal_installed/latest AMO URLs | V F and AMO GUIDs. Policy updates existing extension-specific installation_mode/install_url, intentionally not all pre-existing extension settings. |
| firefox-policy.py:14–22 | 3rdparty Extensions; userSettings advancedUserEnabled string true; advancedSettings userResourcesLocation; toOverwrite filters/list IDs | V F3/B for managed structure and conversion. Local upstream list assets inspected; all actual list downloads and custom script execution U. Overwrite means overwrite, not append. |
| firefox-policy.py:23–39 | released configuration; removal of obsolete list key; equality guards; remove toOverwrite on release; dump | I. Rerun preserves released state. --release cannot prove browser ever applied initial state. Existing unexpected managed config fails rather than silently replacing it. |

## Tests still required before a stronger completion claim

- Disposable real Windows run for every direct installer: normal completion, cancellation, application auto-launch, reboot-required success, retained installed version, damaged registration, custom path.
- Same-user elevated and alternate-credential account context checks.
- WinGet manifest selection on target Windows version; Store policy constraints; PATH refresh after installing uv/Git.
- PowerToys initially missing/installed/running/custom location; actual Win+F2, Everything global/file query and restart persistence.
- Firefox fresh and populated profiles, multiple Windows accounts/installations, release before/after extension startup, existing managed policy, custom profile location; confirm no unrelated filters lost.
- Explicit reference-page validation for every generic PowerShell/Python built-in marked I and every vendor-specific unknown above. This remains outstanding; no claim of complete per-argument authoritative verification is made.

## Follow-up corrections (2026-11-14)

- Custom PowerToys/Everything discovery now checks PATH, registered App Paths default values, standard per-user/machine/x86 locations; component-specific `-PowerToysPath` / `-EverythingPath` handles nonregistered custom installs without guessing a disk location. Explicit paths must exist and use the expected executable filename. App Paths contract: https://learn.microsoft.com/en-us/windows/win32/shell/app-registration . Portable installs remain an explicit-path case; application version compatibility is not inferred.
- Preserved `Start-Process -Wait -PassThru` rather than replacing it with a parent-process-only wait. Microsoft's documented behavior waits descendants: https://learn.microsoft.com/powershell/module/microsoft.powershell.management/start-process . The installer now tells the user to disable final auto-launch, or close an auto-launched app. This is an interactive installer contract, not a claim of unattended completion.
- Firefox initialization now refuses on machines with another non-special Windows user profile. `Win32_UserProfile.Special` identifies system-service profiles and SID identifies ownership: https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile . This conservative guard avoids pretending current-user profiles.ini covers all users. It does **not** inventory arbitrary unregistered Firefox profile directories, ensure browser startup, or migrate existing personal uBlock settings. Use dashboard setup on multi-user machines; no policies are changed in that refusal path. Release-only remains supported. Mozilla installation policy location: https://support.mozilla.org/en-US/kb/customizing-firefox-using-policiesjson . Group Policy precedence and actual browser application remain untested.
- Removed stale assertion that PowerLauncher lacks DSC support; retained narrow JSON merge implementation.

## Independent desktop/Firefox follow-up review (2026-11-14)

Compared the local discovery and Firefox scope changes with current GitHub main using the connected GitHub reader. Reopened Microsoft App Paths and Win32_UserProfile documentation, Mozilla policies.json installation documentation, voidtools command-line documentation and the EverythingPowerToys wiki. Confirmed App Paths uses the default value rather than `Path`, Firefox policy location is beside the selected EXE under `distribution`, and the proposed profile guard uses documented SID/Special properties. The guard is intentionally conservative, not an inventory of all Firefox profiles. Existing query failure propagates before policy writes; release bypass is deliberate.

Reviewed the six-case desktop discovery fixture and four-case Firefox scope fixture by inspection, including mock scope and failure assertions. No Windows/PowerShell executable is available in this workspace, so neither fixture was executed here. All 27 existing Python tests passed locally. Real registry discovery, profile inventory, PowerToys/Everything startup and Firefox policy consumption still require Windows validation. Removed the remaining stale DSC exclusion assertion in configure_powertoys.py; no functional code change was required in this bounded independent pass. This is not a claim that every command in the full installer has been authoritatively verified.
