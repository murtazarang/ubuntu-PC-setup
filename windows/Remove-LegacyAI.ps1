# Remove the old PC-Setup inference stack, without deleting shared model libraries.
[CmdletBinding()]
param([switch]$Apply, [switch]$PurgeQuarantine)
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
function Get-PaseoRegistration {
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($item in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
            if ($item.PSObject.Properties['DisplayName'] -and $item.DisplayName -match '^Paseo(?:$|\s)') { $item }
        }
    }
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
function Show-ExternalLocations {
    foreach ($name in @('STRATA_DATA_DIR','STRATA_INSTALL_DIR','STRATA_HOME','STRATA_SETTINGS_FILE','PASEO_HOME')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { Write-Host "Custom location (retained): $name=$value" }
    }
    $files = @((Join-Path $env:APPDATA 'Strata\settings.json'), (Join-Path $env:LOCALAPPDATA 'Strata\app-settings.json'), (Join-Path $env:APPDATA 'xestrata\settings.json'))
    foreach ($file in $files) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            try {
                $settings = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
                foreach ($key in @('data_dir','installs','models_dir')) {
                    if ($settings.PSObject.Properties[$key]) {
                        Write-Host "Referenced location ($file, $key; not automatically removed): $($settings.$key -join ', ')"
                    }
                }
            } catch { Write-Warning "Could not inspect $file; retained. $($_.Exception.Message)" }
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
    if ($LASTEXITCODE -ne 0) { throw 'OMP cleanup failed; read the error. Config backups, if created, are preserved outside the model quarantine.' }
}
function Invoke-LegacyCleanup {
    if ($env:OS -ne 'Windows_NT') { throw 'This patch is for native Windows.' }
    if ($PurgeQuarantine -and -not $Apply) { throw '-PurgeQuarantine requires -Apply.' }
    $candidates = @(Get-LegacyCandidates)
    $apps = @(Get-PaseoRegistration)
    Write-Host 'Old inference setup inventory:'
    $candidates | Format-Table Kind,Path -AutoSize | Out-Host
    $apps | Select-Object DisplayName,UninstallString | Format-List | Out-Host
    Show-ExternalLocations
    if (-not $Apply) { Write-Host 'Inventory only. Run with -Apply to uninstall Paseo and quarantine the listed app files. No files changed.'; return }
    # Refuse unknown background ownership instead of terminating arbitrary python/node processes.
    foreach ($c in $candidates) { Assert-NoReparse $c.Path }
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
    $uninstalled = @{}
    foreach ($app in $apps) {
        if (-not $app.PSObject.Properties['UninstallString']) { throw 'Paseo has no registered uninstaller. Remove it in Windows Settings, then rerun.' }
        $raw = [string]$app.UninstallString
        $exe = $null
        if ($raw -match '^"([^"\r\n]+\.exe)"\s*$') { $exe=$Matches[1] }
        elseif ($raw -match '^([^"\r\n]+\.exe)\s*$') { $exe=$Matches[1].Trim() }
        if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Paseo has a nonstandard uninstall command. Remove Paseo through Windows Settings, then rerun this patch.' }
        if ($uninstalled.ContainsKey($exe.ToLowerInvariant())) { continue }
        Write-Host 'Opening the registered Paseo uninstaller. Keep chat/user-data removal unchecked.'
        $p = Start-Process -FilePath $exe -Wait -PassThru
        $uninstalled[$exe.ToLowerInvariant()]=$true
        if ($p.ExitCode -notin @(0,3010)) { throw "Paseo uninstall returned $($p.ExitCode). Other app files left in place." }
    }
    if (@(Get-PaseoRegistration).Count) { throw 'Paseo is still registered; finish its uninstaller before retrying.' }
    Remove-OldOmpProvider
    Remove-StrataPathEntry
    if (-not $candidates.Count) { Write-Host 'No old runtime/download files found. Nothing to quarantine.'; return }
    $parent = Join-Path $env:LOCALAPPDATA 'PC-Setup\LegacyAI-Quarantine'
    $backup = Join-Path $parent ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Assert-NoReparse $backup
    $manifest = @()
    $n=0
    foreach ($c in $candidates) {
        Assert-NoReparse $c.Path
        $dest=Join-Path $backup ('{0}-{1}' -f $n,(Split-Path $c.Path -Leaf)); $n++
        $manifest += [pscustomobject]@{Original=$c.Path; Quarantined=$dest;Kind=$c.Kind;State="planned"}
        ConvertTo-Json -InputObject @($manifest) -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
        Move-Item -LiteralPath $c.Path -Destination $dest
        $manifest[-1].State='moved'
        ConvertTo-Json -InputObject @($manifest) -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'manifest.json') -Encoding UTF8
    }
    Write-Host "Old runtime/download files are now inactive, recoverable at: $backup"
    Write-Host 'Quarantine still occupies disk space. External or shared model libraries were not deleted.'
    if ($PurgeQuarantine) {
        Write-Warning "This permanently deletes ONLY this run's quarantine, including any model files within it: $backup"
        if ((Read-Host 'Type DELETE to permanently remove this quarantine; anything else keeps it') -ceq 'DELETE') {
            Assert-NoReparse $backup
            # Refuse child junctions before recursive removal.
            $links=@(Get-ChildItem -LiteralPath $backup -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
            if ($links.Count) { throw 'Quarantine contains a linked item; retained for manual inspection.' }
            Remove-Item -LiteralPath $backup -Recurse -Force
            Write-Host 'This run''s quarantine permanently removed.'
        } else { Write-Host 'Quarantine retained.' }
    }
}
if ($MyInvocation.InvocationName -ne '.') { Invoke-LegacyCleanup }
