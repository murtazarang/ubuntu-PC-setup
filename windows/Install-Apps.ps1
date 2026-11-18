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
    $installArgs = @('install','--exact','--id',$Id,'--source','winget',
        '--accept-source-agreements','--accept-package-agreements','--disable-interactivity','--no-upgrade')
    # Mozilla's WinGet entry also offers MSIX. The JSON-policy stage needs the
    # unpackaged desktop build. Keep --no-upgrade to preserve recognized installs.
    if ($Id -eq 'Mozilla.Firefox') { $installArgs += @('--installer-type','exe') }
    & winget.exe @installArgs
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
# SignalRGB documents this per-user launcher as its installed executable.
# https://docs.signalrgb.com/guides/installation-setup/file-locations/
function Test-SignalRgbInstalled {
    foreach ($engine in @('VortexEngine', 'VortxEngine')) {
        $root = Join-Path $env:LOCALAPPDATA $engine
        if (Test-Path -LiteralPath (Join-Path $root 'SignalRgbLauncher.exe') -PathType Leaf) { return $true }
        foreach ($version in @(Get-ChildItem -LiteralPath $root -Directory -Filter 'app-*' -ErrorAction SilentlyContinue)) {
            foreach ($relative in @('SignalRgb.exe', 'Signal-x64\SignalRgb.exe', 'SignalRgbLauncher.exe')) {
                if (Test-Path -LiteralPath (Join-Path $version.FullName $relative) -PathType Leaf) { return $true }
            }
        }
    }
    return $false
}
function Run-Installer([string]$Uri, [string]$Name, [string]$ExpectedSha256 = '', [string]$DisplayNamePattern, [switch]$SignalRgb) {
    if (-not $DisplayNamePattern) { throw 'An application detection pattern is required.' }
    if ((Test-DirectAppInstalled $DisplayNamePattern) -or ($SignalRgb -and (Test-SignalRgbInstalled))) {
        Write-Host "$Name installation detected; preserving the installed version."
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
    Write-Host "Starting $Name. Complete any installer prompts. Uncheck Launch at the end if offered."
    Write-Host 'Setup waits for the installer and its child processes. If the installed app opens and setup keeps waiting, close that app to continue.'
    $p = Start-Process -FilePath $file -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "$Name exited with code $($p.ExitCode); check the installer result before rerunning." }
    if (-not ((Test-DirectAppInstalled $DisplayNamePattern) -or ($SignalRgb -and (Test-SignalRgbInstalled)))) {
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
    'Stremio.Stremio', 'Microsoft.VisualStudioCode',
    'Microsoft.PowerToys', '7zip.7zip',
    'Microsoft.DotNet.DesktopRuntime.10', 'Microsoft.VCRedist.2015+.x64'
)
foreach ($app in $packages) { Install-WingetApp $app }
Install-Spotify
# Use the exact SignalRGB installer supplied by the user.
Run-Installer 'https://release.signalrgb.com/Install_SignalRgb.exe' 'Install_SignalRgb.exe' -DisplayNamePattern '^SignalRGB(?:$|\s)' -SignalRgb
Write-Host 'Application installer stage finished.'


