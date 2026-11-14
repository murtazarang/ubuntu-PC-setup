# Follow-up boot/update audit (2026-11-14)

Fresh reads used GitHub main, not the stale local launcher. Inspected current
run.ps1, Bootstrap.ps1, Install-Drivers.ps1, Install-Updates.ps1 and update tests
against the outstanding entries in audit-boot.md. No installer was launched.

## Narrow changes prepared

1. Deferred Windows Update names are printed before the first download. Previously
   a download failure, installer failure or reboot throw skipped these diagnostics.
2. A failed/partially successful installation with RebootRequired now reports both
   the unsuccessful result and the restart requirement. It still stops the stage.
3. Three added mocked cases cover those paths and failure without a restart.

No update-selection criteria, user settings or installed software are changed by
this patch. Existing mock fixture result codes were parameterized.

## Sources checked afresh

- https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nn-wuapi-iinstallationresult
  ResultCode and RebootRequired are separate result properties. The latter indicates
  restart is needed to complete installation; generic operation failure does not
  replace this information.
- https://learn.microsoft.com/en-us/windows/win32/api/wuapi/ne-wuapi-operationresultcode
  2 means success; 3 is completed with errors/incomplete results; 4 is failure.
- https://learn.microsoft.com/en-us/windows/win32/api/wuapi/nf-wuapi-iupdatesearcher-search
  Existing query is valid, including its Software restriction. BrowseOnly=0 would
  exclude optional updates. The current query includes them; left unchanged because
  this is update policy, not invalid syntax.
- https://learn.microsoft.com/en-us/windows/package-manager/winget/install
  Bootstrap/launcher --id, --exact, --source, agreement flags and --no-upgrade are
  documented. No-upgrade is not executable health verification.
- https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process?view=powershell-7.6
  Driver app invocation FilePath/Wait/PassThru is documented; descendant-process
  waiting can delay completion. This does not verify vendor installation/exit codes.

## Remaining uncertainties, not marked passed

- No local pwsh executable. New PowerShell cases require Windows CI execution.
- Real NVIDIA/Intel installer registry names, success/reboot codes and installer
  lifecycle remain vendor/runtime unknowns. Kept conservative existing checks.
- Actual installed-MSIX launch remains separate from candidate/probe mocked tests.
- Bootstrap is a manual helper: from 5.1 it can invoke WinGet even if 7 is already
  installed, then instructs opening 7. It does not use the launcher's post-install
  health probe. This is not the reported one-line launcher failure path.
- No claim that every Microsoft command or every actual Windows execution is
  verified by this follow-up. The old audit ledger's FIX/pending language also
  needs its provenance updated by coordinator to the actual subsequent CI runs.
## Applications follow-up: actual current-main check (2026-11-14)

Read current GitHub main Install-Apps.ps1 and audit-apps.md, rather than treating the local checkout as current. Found a discrepancy: the ledger said the direct-installer wait guidance was present, but the actual main script still said only 'Complete any installer prompts.' The proposed narrow correction explains the final Launch checkbox and closing an auto-launched app if setup remains waiting. It deliberately retains process-tree waiting so a child installer cannot be abandoned prematurely.

Authoritative evidence reopened:
- Microsoft Start-Process reference: FilePath, Wait, PassThru are supported, PassThru returns the Process object, and Wait waits for descendants. https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process
- Microsoft WinGet install reference: --exact, --id, --source, --accept-source-agreements, --accept-package-agreements, --disable-interactivity and --no-upgrade are documented. --no-upgrade skips an installed version; --disable-interactivity is distinct from --silent. https://learn.microsoft.com/en-us/windows/package-manager/winget/install
- Current upstream AppInstallerErrors.h directly fetched: 0x8A150061 is PACKAGE_ALREADY_INSTALLED and 0x8A15010D is INSTALL_ALREADY_INSTALLED. The existing accepted-status handling matches those definitions. https://raw.githubusercontent.com/microsoft/winget-cli/master/src/AppInstallerSharedLib/Public/AppInstallerErrors.h
- Exact Paseo v0.16.0-beta.2 local git object b7605043878e509699bf2d8428253a257dda478d: packages/desktop/electron-builder.yml explicitly sets NSIS oneClick=false, perMachine=false, allowToChangeInstallationDirectory=true and the expected Windows artifact naming pattern. This establishes the tagged configuration, not execution of its binary. https://github.com/getpaseo/paseo/blob/v0.16.0-beta.2/packages/desktop/electron-builder.yml

Validation performed: one Python source-regression test proves the guidance precedes the retained process-tree wait. No Windows runtime, installer, registry, service or browser operation was run in this pass.

Still unknown: each direct installer's actual exit/registration/auto-launch behavior; Store restrictions; exact target-machine WinGet manifest selection; arbitrary portable app detection; actual PowerToys/Everything hotkey and plugin load; browser policy application. Installed-file or registration detection is not application-health verification. This pass does not finish every generic command's documentation audit.
