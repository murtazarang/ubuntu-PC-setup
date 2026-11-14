# Install Windows applications on the user's own Windows PC.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'WinGet is unavailable. Install or repair Microsoft App Installer, then rerun.'
}
function Install-WingetApp([string]$Id) {
    Write-Host "Installing $Id ..."
    & winget.exe install --exact --id $Id --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade
    $code = '0x{0:X8}' -f ([long]$LASTEXITCODE -band 0xFFFFFFFFL)
    # APPINSTALLER_CLI_ERROR_INSTALL_ALREADY_INSTALLED
    if ($code -notin @('0x00000000', '0x8A150061', '0x8A15010D')) { throw "winget $Id failed, exit code $code" }
}
function Run-Installer([string]$Uri, [string]$Name, [string]$ExpectedSha256 = '') {
    $folder = Join-Path $env:TEMP 'UbuntuPCSetup-Windows'
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $file = Join-Path $folder $Name
    Write-Host "Downloading $Name"
    Invoke-WebRequest -Uri $Uri -OutFile $file
    if ($ExpectedSha256) {
        $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
        if ($actual -ne $ExpectedSha256) { throw "SHA-256 mismatch for $Name" }
    }
    Write-Host "Starting $Name. Complete any installer prompts."
    $p = Start-Process -FilePath $file -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "$Name exited with code $($p.ExitCode)" }
}
$packages = @(
    'Git.Git', 'astral-sh.uv', 'Mozilla.Firefox', 'Valve.Steam',
    'Stremio.Stremio', 'Foundry376.Mailspring', 'Microsoft.VisualStudioCode',
    'Spotify.Spotify', 'Microsoft.PowerToys', '7zip.7zip',
    'Microsoft.DotNet.DesktopRuntime.10', 'Microsoft.VCRedist.2015+.x64'
)
foreach ($app in $packages) { Install-WingetApp $app }
# Pin the user's selected Paseo beta and the official Windows asset.
Run-Installer 'https://github.com/getpaseo/paseo/releases/download/v0.16.0-beta.2/Paseo-Setup-0.16.0-beta.2-x64.exe' 'Paseo-Setup-0.16.0-beta.2-x64.exe' 'd957b0b9978ef9283f6b794f0cd950563fc849b6f00266bea709fba903ed442f'
# These are the exact installers supplied by the user, not substituted versions.
Run-Installer 'https://github.com/Rem0o/FanControl.Releases/releases/download/V285/FanControl_285_net_4_8_Installer.exe' 'FanControl_285_net_4_8_Installer.exe'
Run-Installer 'https://release.signalrgb.com/Install_SignalRgb.exe' 'Install_SignalRgb.exe'
# Install ArtCraft Studio using the publisher's current Windows x64 installer.
$release = Invoke-RestMethod -Uri 'https://api.github.com/repos/storytold/artcraft/releases/latest'
$assets = @($release.assets | Where-Object { $_.name -match '^ArtCraft_.*_x64-setup\.exe$' })
if ($assets.Count -ne 1) { throw 'Could not uniquely identify the official ArtCraft Studio Windows installer.' }
Run-Installer $assets[0].browser_download_url $assets[0].name
Write-Host 'Application installer stage finished.'
