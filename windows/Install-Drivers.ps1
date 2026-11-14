# Install the GPU vendor's management app, not a fixed graphics driver.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Hardware -like 'Nvidia*') {
    $name = 'NVIDIA_app_x64.exe'
    $url = 'https://us.download.nvidia.com/nvapp/client/11.0.9.585/x64/NVIDIA_app_v11.0.9.585_x64.exe'
    $app = 'NVIDIA App'
} else {
    $name = 'Intel-Driver-and-Support-Assistant-Installer.exe'
    $url = 'https://dsadata.intel.com/installer'
    $app = 'Intel Driver & Support Assistant'
}
$file = Join-Path $env:TEMP $name
Invoke-WebRequest -Uri $url -OutFile $file
Write-Host "Start the $app installer and complete its prompts."
$p = Start-Process -FilePath $file -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "$app installer exited with $($p.ExitCode); verify its installation before continuing." }
Write-Host "Open $app, install the recommended graphics driver, and reboot before running the Desktop stage."
