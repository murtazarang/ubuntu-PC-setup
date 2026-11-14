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
function Test-DirectAppInstalled([string]$DisplayNamePattern) {
    # Apps & Features registration is the Windows installer contract. Do not
    # replace an older/newer registered version merely to match today's setup.
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
            if ($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -match $DisplayNamePattern) { return $true }
        }
    }
    return $false
}
function Run-Installer([string]$Uri, [string]$Name, [string]$ExpectedSha256 = '', [string]$DisplayNamePattern) {
    if (-not $DisplayNamePattern) { throw 'An application detection pattern is required.' }
    if (Test-DirectAppInstalled $DisplayNamePattern) {
        Write-Host "$Name application already registered; preserving the installed version."
        return
    }
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
    if ($p.ExitCode -ne 0) { throw "$Name exited with code $($p.ExitCode); check the installer result before rerunning." }
    if (-not (Test-DirectAppInstalled $DisplayNamePattern)) {
        throw "$Name returned but no matching installation is registered. Complete any remaining installer prompts before retrying."
    }
}
function Test-SpotifyInstalled {
    # Preserve either an existing Win32 installation or the user's Store package.
    foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                       'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        foreach ($entry in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
            if ($entry.PSObject.Properties['DisplayName'] -and $entry.DisplayName -match '^Spotify(?:$|\s)') { return $true }
        }
    }
    if (Test-Path -LiteralPath (Join-Path $env:APPDATA 'Spotify\Spotify.exe')) { return $true }
    # Appx is a Windows PowerShell module. Query it in the built-in host rather
    # than depending on its compatibility with the current PowerShell 7 build.
    $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $windowsPowerShell -NoProfile -NonInteractive -Command '$ErrorActionPreference = "Stop"; try { if (Get-AppxPackage -Name SpotifyAB.SpotifyMusic) { exit 0 }; exit 1 } catch { Write-Error $_; exit 2 }'
    if ($LASTEXITCODE -eq 0) { return $true }
    if ($LASTEXITCODE -eq 1) { return $false }
    throw 'Could not determine whether Spotify is installed; refusing to install a duplicate.'
}
function Install-Spotify {
    if (Test-SpotifyInstalled) { Write-Host 'Spotify is already installed; preserving it.'; return }
    # Spotify's Win32 installer prohibits elevation. Use its official Store
    # distribution instead; this installation has NOT been hardware-tested.
    & winget.exe install --id 9NCBCSZSJRSB --exact --source msstore --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade
    $code = '0x{0:X8}' -f ([long]$LASTEXITCODE -band 0xFFFFFFFFL)
    if ($code -notin @('0x00000000', '0x8A150061', '0x8A15010D')) { throw "Spotify Store installation failed ($code)." }
    if (-not (Test-SpotifyInstalled)) { throw 'Spotify installation returned without a detectable installation.' }
}
$packages = @(
    'Git.Git', 'astral-sh.uv', 'Mozilla.Firefox', 'Valve.Steam',
    'Stremio.Stremio', 'Foundry376.Mailspring', 'Microsoft.VisualStudioCode',
    'Microsoft.PowerToys', '7zip.7zip',
    'Microsoft.DotNet.DesktopRuntime.10', 'Microsoft.VCRedist.2015+.x64'
)
foreach ($app in $packages) { Install-WingetApp $app }
Install-Spotify
# Pin the user's selected Paseo beta and the official Windows asset.
Run-Installer 'https://github.com/getpaseo/paseo/releases/download/v0.16.0-beta.2/Paseo-Setup-0.16.0-beta.2-x64.exe' 'Paseo-Setup-0.16.0-beta.2-x64.exe' 'd957b0b9978ef9283f6b794f0cd950563fc849b6f00266bea709fba903ed442f' -DisplayNamePattern '^Paseo(?:$|\s)' 
# These are the exact installers supplied by the user, not substituted versions.
Run-Installer 'https://github.com/Rem0o/FanControl.Releases/releases/download/V285/FanControl_285_net_4_8_Installer.exe' 'FanControl_285_net_4_8_Installer.exe' -DisplayNamePattern '^Fan ?Control(?:$|\s)'
Run-Installer 'https://release.signalrgb.com/Install_SignalRgb.exe' 'Install_SignalRgb.exe' -DisplayNamePattern '^SignalRGB(?:$|\s)'
# Install ArtCraft Studio using the publisher's current Windows x64 installer.
if (Test-DirectAppInstalled '^ArtCraft(?:$|\s)') {
    Write-Host 'ArtCraft is already registered; preserving the installed version.'
} else {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/storytold/artcraft/releases/latest'
    $assets = @($release.assets | Where-Object { $_.name -match '^ArtCraft_.*_x64-setup\.exe$' })
    if ($assets.Count -ne 1) { throw 'Could not uniquely identify the official ArtCraft Studio Windows installer.' }
    Run-Installer $assets[0].browser_download_url $assets[0].name -DisplayNamePattern '^ArtCraft(?:$|\s)'
}
Write-Host 'Application installer stage finished.'
