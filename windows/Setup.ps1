#Requires -Version 7.0
# Native Windows stages; run in PowerShell 7 as the logged-in user's administrator.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('Drivers','Desktop')][string]$Stage,
    [Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,
    [string]$ArchiveDirectory = (Join-Path $env:LOCALAPPDATA 'OpenZIM\archives')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This setup is for native Windows only.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run PowerShell 7 as administrator under the account to be configured.'
}
if ($Stage -eq 'Drivers') {
    & (Join-Path $PSScriptRoot 'Install-Updates.ps1')
    & (Join-Path $PSScriptRoot 'Install-Drivers.ps1') -Hardware $Hardware
    Write-Host 'Use the installed vendor app to install its recommended graphics driver, reboot, then run the Desktop stage.'
    return
}

& (Join-Path $PSScriptRoot 'Install-Apps.ps1')
# Refresh persisted paths without discarding process-only entries or precedence.
$pathEntries = [System.Collections.Generic.List[string]]::new()
foreach ($pathSource in @(
    $env:Path,
    [Environment]::GetEnvironmentVariable('Path','Machine'),
    [Environment]::GetEnvironmentVariable('Path','User'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
    (Join-Path $env:USERPROFILE '.local\bin')
)) {
    foreach ($entry in ($pathSource -split ';')) {
        if ($entry -and $entry -notin $pathEntries) { $pathEntries.Add($entry) }
    }
}
$env:Path = $pathEntries -join ';'
& (Join-Path $PSScriptRoot 'Install-OMP.ps1')
& (Join-Path $PSScriptRoot 'Configure-Desktop.ps1')
& (Join-Path $PSScriptRoot 'Install-Skills.ps1')
& (Join-Path $PSScriptRoot 'Configure-Firefox.ps1')
& (Join-Path $PSScriptRoot 'Install-Reference.ps1') -ArchiveDirectory $ArchiveDirectory
& (Join-Path $PSScriptRoot 'Install-Model.ps1') -Hardware $Hardware
Write-Host 'Desktop stages finished. Read the Windows README for first-run and verification.'
