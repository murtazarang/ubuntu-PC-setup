# Must run as an administrator because Firefox's distribution policy is machine-wide.
[CmdletBinding()]
param([switch]$Release)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# A distribution policy reaches every profile using this Firefox installation.
# Do not infer that another user's redirected/custom Firefox profiles are absent.
# Special excludes system-service profiles per Win32_UserProfile documentation.
# https://learn.microsoft.com/en-us/previous-versions/windows/desktop/userprofileprov/win32-userprofile
if (-not $Release) {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $otherProfiles = @(Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
        Where-Object { -not $_.Special -and $_.SID -ne $currentSid })
    if ($otherProfiles.Count -gt 0) {
        throw 'Other Windows user profiles exist. No Firefox policies were changed: this installation-wide policy could replace their uBlock filters. Configure the requested extensions and filters in your own Firefox dashboard instead. Release-only remains available for a previous setup.'
    }
}
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
# WinGet may preserve an existing per-user, x86 or custom-path installation.
$candidates = @()
foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
                   'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe',
                   'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe')) {
    if (Test-Path -LiteralPath $key) { $candidates += (Get-Item -LiteralPath $key).GetValue('') }
}
$candidates += Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe'
if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'Mozilla Firefox\firefox.exe' }
$candidates += Join-Path $env:LOCALAPPDATA 'Mozilla Firefox\firefox.exe'
$firefox = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $firefox) { throw 'Firefox not found in registered or standard installation locations.' }
# Microsoft Store/MSIX package files are read-only, including for administrators.
if (($firefox -split '[\\/]') -contains 'WindowsApps') {
    throw 'The discovered Firefox is a protected Microsoft Store package. No policies were changed. This JSON-policy setup requires the Mozilla desktop build; do not change WindowsApps permissions.'
}
$policy = Join-Path (Split-Path $firefox) 'distribution\policies.json'
$argsList = @('run','--no-project','python',(Join-Path $PSScriptRoot 'apply_firefox_policy.py'),$policy,'--profiles',(Join-Path $env:APPDATA 'Mozilla\Firefox\profiles.ini'))
if ($Release) { $argsList += '--release' }
& $uv @argsList
if ($LASTEXITCODE -ne 0) { throw 'Firefox policy merge failed. Check permissions and existing policies.' }
if (-not $Release) {
    Write-Host 'Start Firefox once and allow extensions to initialize, then run this script with -Release to preserve later uBlock filter edits.'
} else { Write-Host 'Released initial uBlock filter settings; other policies remain.' }

