# Install the GPU vendor's management app, not a fixed graphics driver.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Hardware -like 'Nvidia*') {
    $name = 'NVIDIA_app_x64.exe'
    $url = 'https://us.download.nvidia.com/nvapp/client/11.0.9.585/x64/NVIDIA_app_v11.0.9.585_x64.exe'
    $app = 'NVIDIA App'
    $displayPattern = '^NVIDIA App$'
} else {
    $name = 'Intel-Driver-and-Support-Assistant-Installer.exe'
    $url = 'https://dsadata.intel.com/installer'
    $app = 'Intel Driver & Support Assistant'
    $displayPattern = '^Intel.*Driver.*Support Assistant'
}
# Check both 64-bit and 32-bit uninstall registries, including the current user.
$uninstallPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$installed = @(Get-ItemProperty -Path $uninstallPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -match $displayPattern })
if ($installed.Count -gt 0) {
    Write-Host "$app is already installed; leaving it unchanged."
    Write-Host "Open $app, install the recommended graphics driver, and reboot before the Desktop stage."
    return
}
$file = Join-Path $env:TEMP $name
Invoke-WebRequest -Uri $url -OutFile $file
Write-Host "Start the $app installer and complete its prompts."
$p = Start-Process -FilePath $file -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "$app installer exited with $($p.ExitCode); verify its installation before continuing." }
Write-Host "Open $app, install the recommended graphics driver, and reboot before running the Desktop stage."
