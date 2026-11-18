# Remove the old PC-Setup inference stack, without deleting shared model libraries.
[CmdletBinding()]
param([switch]$Apply,[switch]$RequireRemoval,[switch]$SkipOmpConfig)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-UnderPath([string]$Path, [string]$Root) {
    $p = [IO.Path]::GetFullPath($Path).Replace('/','\').TrimEnd('\')
    $r = [IO.Path]::GetFullPath($Root).Replace('/','\').TrimEnd('\')
    return $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Assert-NoReparse([string]$Path) {
    $item = Get-Item -LiteralPath $Path -Force
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing linked path: $($item.FullName)" }
        $item = if ($item -is [IO.DirectoryInfo]) { $item.Parent } else { $item.Directory }
    }
}
function Get-SafeLegacyLinks([string]$Path) {
    Assert-NoReparse $Path
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    foreach ($link in @(Get-ChildItem -LiteralPath $Path -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })) {
        # Strata's official installer creates exactly this junction (packaging/install.ps1).
        $terminal=Join-Path $env:LOCALAPPDATA 'Strata\terminal'
        $current=Join-Path $terminal 'current'
        $targets=@($link.Target)
        if ($link.FullName -ine $current -or $link.LinkType -ne 'Junction' -or $targets.Count -ne 1 -or
            -not [IO.Path]::IsPathRooted([string]$targets[0]) -or -not (Test-UnderPath ([string]$targets[0]) $terminal) -or
            ([string]$targets[0]).TrimEnd('\') -ieq $terminal.TrimEnd('\')) {
            throw "Refusing unexpected linked item; no automatic target deletion: $($link.FullName)"
        }
        Assert-NoReparse ([string]$targets[0])
        $link.FullName
    }
}
function Assert-LegacyCorpusAbsent([object[]]$Candidates) {
    $allowed=@()
    foreach($candidate in $Candidates){if(Test-Path -LiteralPath $candidate.Path){$allowed+=@(Get-SafeLegacyLinks $candidate.Path)}}
    & (Join-Path $PSScriptRoot 'Assert-NoCorpus.ps1') -CandidatePaths @($Candidates|ForEach-Object {$_.Path}) -AllowedLinks $allowed
}
function Get-LocationDisposition([string]$Path, [object[]]$Candidates) {
    if ($Path -and [IO.Path]::IsPathRooted($Path)) {
        foreach ($candidate in $Candidates) {
            if (Test-UnderPath $Path $candidate.Path) { return 'inside a listed runtime/download; included in permanent removal, including local settings/model files' }
        }
    }
    if (-not $Path -or -not [IO.Path]::IsPathRooted($Path)) { return 'not absolute; not resolved or independently added; inspect against listed parent cleanup paths' }
    return 'outside the listed cleanup paths; retained'
}
function Show-ExistingQuarantines([string]$Parent) {
    if (-not (Test-Path -LiteralPath $Parent)) { return }
    Assert-NoReparse $Parent
    foreach ($directory in @(Get-ChildItem -LiteralPath $Parent -Directory -Force)) {
        Write-Host "Previous quarantine retained (not purged by this run): $($directory.FullName)"
    }
}
function Get-PaseoRegistration {
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($item in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
            if ($item.PSObject.Properties['DisplayName'] -and $item.DisplayName -match '^Paseo(?:$|\s)') { $item }
        }
    }
}
function Resolve-PaseoUninstallCommand([string]$Command) {
    # electron-builder's NSIS registry command includes the install scope.
    # Parse data only: never evaluate a registry value as PowerShell or cmd.exe.
    $exe=$null; $scope=$null
    if ($Command -match '^"([^"\r\n]+\.exe)"(?:\s+(/currentuser|/allusers))?\s*$') {
        $exe=$Matches[1]; if ($Matches.ContainsKey(2)) { $scope=$Matches[2] }
    } elseif ($Command -match '^([^"\r\n]+\.exe)(?:\s+(/currentuser|/allusers))?\s*$') {
        $exe=$Matches[1].Trim(); if ($Matches.ContainsKey(2)) { $scope=$Matches[2] }
    }
    if (-not $exe) { throw 'Unrecognized Paseo uninstall command; nothing executed. Remove Paseo through Windows Settings, then rerun.' }
    [pscustomobject]@{Executable=$exe;Scope=$scope}
}
function Invoke-PaseoUninstaller($Command) {
    if (-not (Test-Path -LiteralPath $Command.Executable -PathType Leaf)) { throw 'Registered Paseo uninstaller was not found; no uninstall command executed.' }
    $parameters=@{FilePath=$Command.Executable;Wait=$true;PassThru=$true}
    if ($Command.Scope) { $parameters.ArgumentList=@([string]$Command.Scope) }
    Start-Process @parameters
}
function Get-LegacyCandidates {
    # Exact destinations used by this repository and upstream's standard installer.
    # Custom locations are reported, never inferred to be ours.
    foreach ($relative in @('Strata','XeStrata-Setup','xestrata')) {
        $path = Join-Path $env:LOCALAPPDATA $relative
        if (Test-Path -LiteralPath $path) { [pscustomobject]@{Path=$path; Kind='runtime/data'} }
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Filter 'xestrata-*' -ErrorAction SilentlyContinue)) {
        if ($dir.Name -match '^xestrata-[0-9a-fA-F]{8}-[0-9a-fA-F-]{27}$') {
            $files=@(Get-ChildItem -LiteralPath $dir.FullName -Force)
            if ($files.Count -gt 0 -and @($files | Where-Object { $_.PSIsContainer -or $_.Name -notmatch '^(XeStrata-.*-windows-x64\.7z|SHA256SUMS)$' }).Count -eq 0) {
                [pscustomobject]@{Path=$dir.FullName;Kind='download'}
            } else { Write-Warning "Unrecognized temporary directory retained: $($dir.FullName)" }
        }
    }
    foreach ($relative in @('strata-install.ps1','UbuntuPCSetup-Windows\Paseo-Setup-0.16.0-beta.2-x64.exe')) {
        $path = Join-Path $env:TEMP $relative
        if (Test-Path -LiteralPath $path) { [pscustomobject]@{Path=$path; Kind='download'} }
    }
}
function Show-ExternalLocations([object[]]$Candidates) {
    foreach ($name in @('STRATA_DATA_DIR','STRATA_INSTALL_DIR','STRATA_HOME','STRATA_SETTINGS_FILE','PASEO_HOME')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { Write-Host "Custom location ($(Get-LocationDisposition $value $Candidates)): $name=$value" }
    }
    $files = @((Join-Path $env:APPDATA 'Strata\settings.json'), (Join-Path $env:LOCALAPPDATA 'Strata\app-settings.json'), (Join-Path $env:APPDATA 'xestrata\settings.json'))
    foreach ($file in $files) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Write-Host "Settings file ($(Get-LocationDisposition $file $Candidates)): $file"
            try {
                $settings = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                foreach ($key in @('data_dir','installs','models_dir')) {
                    if ($settings.PSObject.Properties[$key]) {
                        foreach ($location in @($settings.$key)) {
                            Write-Host "Referenced location ($file, $key; $(Get-LocationDisposition ([string]$location) $Candidates)): $location"
                        }
                    }
                }
            } catch { Write-Warning "Could not parse references in $file; the file disposition printed above still applies. $($_.Exception.Message)" }
        }
    }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    if ($documents) {
        $library = Join-Path $documents 'Strata'
        if (Test-Path -LiteralPath $library) { Write-Host "Potential model library retained: $library" }
    }
    Write-Host 'Chat/settings directories (.paseo, .strata, roaming app data), OMP, skills, OpenZIM, Wikipedia, shared caches and system packages are retained.'
}
function Remove-StrataPathEntry {
    $target = Join-Path $env:LOCALAPPDATA 'Strata\terminal\current\bin'
    $old = [Environment]::GetEnvironmentVariable('Path','User')
    if (-not $old) { return }
    $new = @($old -split ';' | Where-Object { $_.Trim().TrimEnd('\') -ine $target.TrimEnd('\') }) -join ';'
    if ($new -ne $old) { [Environment]::SetEnvironmentVariable('Path',$new,'User') }
    $env:Path = @($env:Path -split ';' | Where-Object { $_.Trim().TrimEnd('\') -ine $target.TrimEnd('\') }) -join ';'
}
function Remove-OldOmpProvider {
    $omp=Get-Command omp.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $omp) { Write-Warning 'OMP is not on PATH; its settings were retained. Run this patch from a session where omp.exe is available to remove the old provider.'; return }
    $uv=Get-Command uv.exe -CommandType Application -ErrorAction SilentlyContinue
    if (-not $uv) { Write-Warning 'uv is unavailable; OMP provider was retained. No shared dependencies are removed by this patch.'; return }
    $backup=Join-Path $env:LOCALAPPDATA ('PC-Setup\LegacyAI-Config-Backup\'+[guid]::NewGuid().ToString())
    & $uv.Source run --no-project --with PyYAML python (Join-Path $PSScriptRoot 'cleanup_legacy_config.py') --omp $omp.Source --backup $backup
    if ($LASTEXITCODE -ne 0) { throw 'OMP cleanup failed; read the error. Config backups, if created, are preserved outside the runtime deletion paths.' }
}
function Invoke-LegacyCleanup {
    if ($env:OS -ne 'Windows_NT') { throw 'This patch is for native Windows.' }
    Show-ExistingQuarantines (Join-Path $env:LOCALAPPDATA 'PC-Setup\LegacyAI-Quarantine')
    $candidates = @(Get-LegacyCandidates)
    Assert-LegacyCorpusAbsent $candidates
    $apps = @(Get-PaseoRegistration)
    Write-Host 'Old inference setup inventory:'
    foreach ($candidate in $candidates) { Write-Host ("[{0}] {1}" -f $candidate.Kind,$candidate.Path) }
    $apps | Select-Object DisplayName,UninstallString | Format-List | Out-Host
    Show-ExternalLocations $candidates
    if (-not $Apply) { Write-Host 'Inventory only. Run with -Apply to uninstall Paseo and permanently remove the listed app files. No files changed.'; return }
    function Assert-LegacyNotRunning([object[]]$candidates) {
    # Refuse unknown background ownership instead of terminating arbitrary python/node processes.
    foreach ($c in $candidates) { $null = @(Get-SafeLegacyLinks $c.Path) }
    foreach ($process in @(Get-CimInstance Win32_Process -ErrorAction Stop)) {
        $pathMatch=$process.ExecutablePath -and @($candidates | Where-Object { Test-UnderPath $process.ExecutablePath $_.Path }).Count
        $commandMatch=$process.PSObject.Properties['CommandLine'] -and $process.CommandLine -and @($candidates | Where-Object { $process.CommandLine.IndexOf($_.Path,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count
        if ($pathMatch -or $commandMatch) {
            throw "Close the old inference application (PID $($process.ProcessId)) and rerun. No cleanup started."
        }
    }
    foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction Stop)) {
        foreach ($c in $candidates) {
            if ($service.PathName -and $service.PathName.IndexOf($c.Path,[StringComparison]::OrdinalIgnoreCase) -ge 0) { throw "Service '$($service.Name)' uses $($c.Path); retained. Stop/uninstall it through its own manager before cleanup." }
        }
    }
    }
    Assert-LegacyNotRunning $candidates
    Assert-LegacyCorpusAbsent $candidates
    if ($apps.Count -or $candidates.Count) {
        Write-Warning 'The listed runtime/download paths will be permanently deleted, including models and local settings inside them. Paseo will be uninstalled. No quarantine is created. External/shared libraries and separate chat/settings roots remain untouched.'
        if ((Read-Host 'Type DELETE to uninstall/remove exactly the listed items; anything else cancels without changes') -cne 'DELETE') {
            Write-Host 'Cancelled. No uninstall, configuration change or file deletion performed.'
            if($RequireRemoval){throw 'Legacy removal declined; migration cleanup is incomplete.'}
            return
        }
    }
    # Recheck after the user confirmation, immediately before any uninstall/deletion.
    Assert-LegacyNotRunning $candidates
    Assert-LegacyCorpusAbsent $candidates
    $uninstalled = @{}
    foreach ($app in $apps) {
        if (-not $app.PSObject.Properties['UninstallString']) { throw 'Paseo has no registered uninstaller. Remove it in Windows Settings, then rerun.' }
        $command=Resolve-PaseoUninstallCommand ([string]$app.UninstallString)
        $identity=$command.Executable.ToLowerInvariant()+'|'+[string]$command.Scope
        if ($uninstalled.ContainsKey($identity)) { continue }
        Write-Host 'Opening the registered Paseo uninstaller. This patch does not request deletion of Paseo user data.'
        $p=Invoke-PaseoUninstaller $command
        $uninstalled[$identity]=$true
        if ($p.ExitCode -notin @(0,3010)) { throw "Paseo uninstall returned $($p.ExitCode). Other app files left in place." }
    }
    if (@(Get-PaseoRegistration).Count) { throw 'Paseo is still registered; finish its uninstaller before retrying.' }
    if(-not $SkipOmpConfig){Remove-OldOmpProvider}
    Remove-StrataPathEntry
    if (-not $candidates.Count) { Write-Host 'No old runtime/download files found. Nothing to delete.'; return }
    $removed=@()
    foreach ($c in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $c.Path)) { continue }
            Assert-LegacyCorpusAbsent @($c)
            foreach ($link in @(Get-SafeLegacyLinks $c.Path)) {
                # Nonrecursive removal deletes the junction, never its target.
                [IO.Directory]::Delete($link)
            }
            Remove-Item -LiteralPath $c.Path -Recurse -Force -ErrorAction Stop
            $removed += $c.Path
            Write-Host "Removed: $($c.Path)"
        } catch {
            throw "Cleanup stopped at $($c.Path), which may be partly removed. Already removed: $($removed -join '; '). Earlier uninstall/config changes may have completed. No rollback or quarantine exists. Cause: $($_.Exception.Message)"
        }
    }
    if($RequireRemoval -and (@(Get-LegacyCandidates).Count -or @(Get-PaseoRegistration).Count)){throw 'Legacy cleanup did not verify; OMP will not be removed by migration.'}
    Write-Host 'Listed legacy runtime/download files removed. External/shared model libraries and separate chat/settings roots retained.'

}
if ($MyInvocation.InvocationName -ne '.') { Invoke-LegacyCleanup }
