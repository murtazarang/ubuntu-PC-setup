# Boot, orchestration and update audit

Date: 2026-11-14. Scope: run.ps1, Bootstrap.ps1, Setup.ps1,
Install-Updates.ps1, Install-Drivers.ps1. Independent documentation review; no
installers, updates, driver changes or reboots were executed by this reviewer.

## Version and execution provenance

Launcher reviewed remotely on fix/pwsh-msix-detection (7c3718983e1a535cc10aacde3821531548c68483).
The coordinator subsequently reports main 0e0cdc6930da98516a0ffe9bdf9ddee082adafeb,
CI run 43601721313 passing mocked MSI/MSIX discovery under Windows PowerShell 5.1
and PowerShell 7, real preinstalled pwsh/5.1 binary version probing, and direct-file
parameter forwarding. This is coordinator-supplied evidence, not execution by this
reviewer. No actual MSIX installation or complete setup was tested. Local run.ps1
was stale during implementation and was deliberately NOT edited. Its contents must
not replace the reviewed remote launcher.

Changes made locally by this reviewer: preserve process PATH, check WUA search
ResultCode, check installer IsBusy and RebootRequiredBeforeInstallation; extend
WUA mocks and add isolated PATH test. Python suite: 26 tests passed locally. No
pwsh binary is available locally, so newly written PowerShell mocks are NOT YET
EXECUTED. CI must explicitly run tests/test-updates.ps1 and tests/test-setup-path.ps1;
parsing a file is not execution of its assertions.

Statuses: DOC = arguments/defaults checked against official documentation;
FIX = correction implemented locally, pending Windows mock execution;
UNKNOWN = unsupported by runtime/vendor evidence. Line references below refer to
the reviewed pre-edit snapshot; identify edited statements by command as lines move.

## Concrete findings

* FIX Setup 26-29 overwrote process PATH. Now retains existing order and appends
  absent Machine/User/WinGet/local-bin entries; reruns should be idempotent.
* FIX Updates 12 ignored search ResultCode. Failed/partial scans now stop before
  downloading and give recovery instructions instead of suggesting no updates.
* FIX Updates 36 omitted installer IsBusy and reboot-before-install checks.
  Both are checked after download; actionable stop messages avoid starting install.
  There is still an unavoidable race with other installers after the check; COM
  operation errors propagate rather than falsely reporting success.
* Launcher existence-only discovery was insufficient. Coordinator reports main now
  probes the binary version; see provenance above. Actual installed-MSIX launch
  remains unverified.
* OPTIONAL POLICY: current WUA query includes optional/browse-only software.
  BrowseOnly=0 would exclude these. Not changed without coordinating scope.
* UNKNOWN vendor-specific installer success/reboot return codes and exact registry
  DisplayName strings. Do not treat generic MSI codes as proven vendor contracts.
* Update deferred warnings can be bypassed by an earlier reboot/error throw.
  Improving error diagnostics is still desirable, not included in narrow patch.

## run.ps1 command/argument ledger

| Original lines | Command/arguments/defaults | Status and implications |
|---|---|---|
| 1-8,76 | `& {}`, CmdletBinding, string ValidateSet, `@args` | DOC parameter declarations and isolated scope. Coordinator reports direct-file forwarding passed; do not infer every iex/caller-scope permutation passed. [PARAM][SPLAT] |
| 9 | ErrorActionPreference Stop | DOC terminating behavior; native exit codes still need explicit checks. [PREF] |
| 10 | env:OS Windows_NT guard | DOC environment access; not a security boundary. [ENV] |
| 11-15 | WindowsIdentity.GetCurrent, New-Object WindowsPrincipal(identity), IsInRole Administrator | DOC current-token check, no elevation. Different credentials configure that other account. [OBJECT][ROLE] |
| 16-34 | Write-Host, Read-Host positional prompt, switch, throw | DOC Read-Host returns string. Input mapping correct. Whitespace is not normalized. [READ] |
| 35-36 | MSIX default comment | DOC PowerShell 7.6+ WinGet default changed from MSI to MSIX. [INSTALL] |
| 38-39 | Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue; Select-Object -First 1; Test-Path -LiteralPath -PathType Leaf | DOC executable discovery/existence is not compatibility proof. Coordinator reports later version probe added. [COMMAND][PATH] |
| 40-41 | Join-Path ProgramFiles PowerShell\\7\\pwsh.exe | DOC default MSI path, not custom-install discovery; x86 host path interpretation remains an edge case. [INSTALL] |
| 42-43 | Get-Command Get-AppxPackage; Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction Stop; Sort-Object Version -Descending | DOC current-user package enumeration; no AllUsers needed. UNKNOWN real MSIX registration/sort/launch; mocked tests only. [APPX] |
| 44-50 | InstallLocation guard, Join-Path, Test-Path Leaf, null fallback | DOC path handling. A command exception can stop before the final diagnostic. [PATH] |
| 52-54 | discovery then winget.exe | UNKNOWN missing App Installer handling beyond command-not-found; explicit prerequisite guidance desirable. |
| 54 | install --id Microsoft.PowerShell --exact --source winget | DOC exact package/source. Omitted version selects available version; omitted scope, architecture and installer type use WinGet selection defaults. [WINGET] |
| 54 | --accept-source-agreements --accept-package-agreements --no-upgrade --disable-interactivity | DOC agreement acceptance, skip upgrading existing installation, suppress interaction. Does not guarantee runnable executable. [WINGET] |
| 55-56 | LASTEXITCODE unsigned hex; 0, 8A150061, 8A15010D | DOC success/already installed/another version installed. Always require successful executable resolution afterward. Other codes stop; reboot-specific messages could improve guidance. [CODES][AUTO] |
| 57-59 | rerun resolver and throw if absent | DOC logical recovery. Main version probe improves it; actual MSIX install not proven. |
| 60-64 | LOCALAPPDATA GUID run directory, New-Item Directory, Out-Null, Join-Path | No overwrite of earlier runs; no HDD operation. GUID name avoids collision. |
| 65 | Invoke-WebRequest -UseBasicParsing -Uri main.zip -OutFile | DOC 5.1 basic parsing avoids IE dependency. Downloaded main is mutable, so launcher/source revisions can differ. [WEB] |
| 66 | Expand-Archive -LiteralPath -DestinationPath | DOC literal input and new destination. Default does not overwrite existing files. [ZIP] |
| 67-69 | expected GitHub ZIP layout, Test-Path Leaf, Split-Path Parent, Write-Host | Checks required Setup exists before launch. UNKNOWN archive retrieval in this audit. |
| 70 | & candidate -NoProfile -ExecutionPolicy Bypass -File setup -Stage -Hardware | DOC option ordering, script arguments after File; policy override is process-local. [PWSH] |
| 71-74 | LASTEXITCODE check, finally retained-path message | DOC propagates child process failure. Child scripts must themselves propagate native failures. [AUTO] |

## Bootstrap.ps1

| Lines | Coverage | Status |
|---|---|---|
| 1-5 | CmdletBinding, param, Stop, env:OS guard | DOC same semantics above. No admin check before package operation. |
| 6 | PSVersionTable.PSVersion.Major <7 | DOC checks current host, not other installed runtimes. [AUTO] |
| 7 | winget flags identical to launcher | DOC [WINGET]. Existing PS7 while running 5.1 still invokes WinGet unnecessarily. |
| 8-9 | normalized code and three accepted codes | DOC [CODES]. No follow-up executable probe here. |
| 11 | open PS7 as administrator instruction | Manual handoff, not verified installation. Prefer reusing tested resolver if Bootstrap remains supported. |

## Setup.ps1

| Lines | Coverage | Status |
|---|---|---|
| 1-8 | Requires Version 7, Mandatory true Stage/Hardware ValidateSet, ArchiveDirectory default Join-Path LOCALAPPDATA | DOC parameter constraints/default evaluated for executing user. [PARAM][AUTO] |
| 9-10 | Set-StrictMode -Version Latest, Stop | DOC Latest may tighten with future runtime; pinning tested strict mode is optional maintainability improvement. [STRICT][PREF] |
| 11-16 | IsWindows, current identity, WindowsPrincipal new, administrator role | DOC current user/token, not intended-desktop-user verification. [AUTO][ROLE] |
| 17-22 | call Updates; call Drivers -Hardware; return | Paths rooted at PSScriptRoot. Update reboot stops stage before vendor app; rerun required. [AUTO] |
| 24 | call Install-Apps | Correct child path; internals separately reviewed. |
| 26-29 | environment refresh | FIX now List[string], existing process first, persisted Machine then User, required tool paths; split on semicolon, case-insensitive -notin dedup; no persisted env writes. [ENV] |
| 30-33 | OMP, desktop, skills, Firefox child scripts | Correct path resolution; no independent validation of their internals here. |
| 34 | reference script -ArchiveDirectory | Correct explicit forwarding, downstream disk checks separate. |
| 35 | model script -Hardware | Correct explicit forwarding; GPU/model validation separate. |
| 36 | final message | Says stages finished, not hardware verified. Depends on downstream failure propagation. |

## Install-Updates.ps1

| Lines | Coverage | Status |
|---|---|---|
| 1-5 | CmdletBinding, strict, Stop | DOC; direct standalone use lacks admin/OS preflight supplied by Setup. |
| 6-9 | New-Object -ComObject Microsoft.Update.SystemInfo; RebootRequired | DOC pending restart preflight. [WUA][OBJECT] |
| 10-12 | Session; CreateUpdateSearcher; Search(IsInstalled=0 and IsHidden=0 and Type='Software') | DOC valid query excludes drivers. Configured update service default; not explicit Microsoft Update all-products service. Optional updates included. [SEARCH] |
| 12-15 | result processing | FIX ResultCode must equal 2 before collection processing. 3 is partial success, not complete scan. [RESULT][ENUM] |
| 13-14 | Microsoft.Update.UpdateColl, empty manual array | DOC collection creation. [WUA] |
| 15-21 | iterate updates; InstallationBehavior.Impact eq 2; defer | DOC exclusive updates cannot share normal batch. [WUA] |
| 22-25 | EulaAccepted / CanRequestUserInput | DOC avoids automatic new agreement acceptance and interactive batch members. [WUA] |
| 26 | void updates.Add(update) | DOC suppress collection index output. [WUA] |
| 28-33 | Count, CreateUpdateDownloader, Updates assignment, Download, code eq2 | DOC synchronous pattern, fails on partial result. No claim failed download succeeded. [WUA][ENUM] |
| 34-36 | CreateUpdateInstaller, Updates, Install | FIX IsBusy and RebootRequiredBeforeInstallation checked just before Install. Busy/restart messages tell user how to retry. [BUSY][REBOOT][INSTALLUPDATE] |
| 37-38 | result code then RebootRequired | DOC conservative. Partial failure + reboot may produce only generic failure message. [ENUM] |
| 39 | no applicable updates message | FIX reliable only after complete successful search. |
| 40-42 | manual warnings, ForEach-Object Write-Warning | Correct deferred names. May not run if earlier exception; unresolved diagnostic improvement. |

## Install-Drivers.ps1

| Lines | Coverage | Status |
|---|---|---|
| 1-5 | Mandatory Hardware ValidateSet, strict, Stop | DOC installs management apps, not GPU driver automatically. |
| 6-10 | Nvidia branch; exact 11.0.9.585 URL; regex ^NVIDIA App$ | DOC URL independently obtained from NVIDIA official page. UNKNOWN actual ARP DisplayName and installer runtime. [NVIDIA] |
| 11-16 | Intel branch; dsadata.intel.com/installer; regex | DOC URL independently obtained from Intel DSA Download now. UNKNOWN ARP field. [INTEL] |
| 17-24 | three registry paths; Get-ItemProperty -Path array -ErrorAction SilentlyContinue; Where-Object guarded DisplayName -match | DOC wildcard registry retrieval. Process bitness affects view. Installed-entry heuristic, not health check. [REGISTRY] |
| 25-29 | skip existing app, instructions, return | Preserves installation and matches user request to use vendor apps. |
| 30-31 | TEMP/name, Invoke-WebRequest -Uri -OutFile | DOC download path. Fixed filename can collide with concurrent runs. [WEB] |
| 32-33 | Start-Process -FilePath -Wait -PassThru | DOC intentionally interactive; waits tree and returns process object. No invented silent arguments. [PROCESS] |
| 34 | ExitCode must equal zero | UNKNOWN vendor reboot-success codes. Conservative error asks user to verify; do not invent whitelist. |
| 35 | open app/install driver/reboot message | Manual step, not verification of app registration. No post-install detection yet. |

## Official sources read

[PARAM]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-7.6
[SPLAT]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_splatting
[PREF]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_preference_variables?view=powershell-7.6
[ENV]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_environment_variables?view=powershell-7.6
[OBJECT]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/new-object?view=powershell-5.1
[ROLE]: https://learn.microsoft.com/en-us/dotnet/api/system.security.principal.windowsprincipal.isinrole
[READ]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/read-host?view=powershell-5.1
[INSTALL]: https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows?view=powershell-7.6
[COMMAND]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/get-command?view=powershell-5.1
[PATH]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/test-path?view=powershell-5.1
[APPX]: https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage?view=windowsserver2025-ps
[WINGET]: https://learn.microsoft.com/en-us/windows/package-manager/winget/install
[CODES]: https://github.com/microsoft/winget-cli/blob/master/doc/windows/package-manager/winget/returnCodes.md
[AUTO]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_automatic_variables?view=powershell-7.6
[WEB]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/invoke-webrequest?view=powershell-5.1
[ZIP]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.archive/expand-archive?view=powershell-7.6
[PWSH]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_pwsh?view=powershell-7.6
[STRICT]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/set-strictmode?view=powershell-7.6
[WUA]: https://learn.microsoft.com/en-us/windows/win32/wua_sdk/searching--downloading--and-installing-updates
[SEARCH]: https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search
[RESULT]: https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-isearchresult
[ENUM]: https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-operationresultcode
[BUSY]: https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-get_isbusy
[REBOOT]: https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-get_rebootrequiredbeforeinstallation
[INSTALLUPDATE]: https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdateinstaller-install
[NVIDIA]: https://www.nvidia.com/en-us/software/nvidia-app/
[INTEL]: https://www.intel.com/content/www/us/en/support/detect.html
[REGISTRY]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-itemproperty?view=powershell-7.6
[PROCESS]: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.6
