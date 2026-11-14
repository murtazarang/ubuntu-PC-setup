# Explicit driver stage. Official Windows WHQL installers for the target GPUs.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$cards = @(Get-CimInstance Win32_VideoController)
if ($Hardware -like 'Nvidia*') {
    $count = @($cards | Where-Object { $_.PNPDeviceID -match 'VEN_10DE' }).Count
    $expected = if ($Hardware -eq 'NvidiaDual') { 2 } else { 1 }
    if ($count -ne $expected) { throw "Expected $expected NVIDIA adapters; Windows reports $count. Check Device Manager." }
    $url = 'https://us.download.nvidia.com/Windows/621.24/621.24-desktop-win10-win11-64bit-international-dch-whql.exe'
    $hash = 'affd77016f389ac44c4f3dddaf937d66403af80c5f6b537ed98ac923ad0f5c81'
    $algorithm = 'SHA256'
} else {
    if (-not @($cards | Where-Object { $_.PNPDeviceID -match 'VEN_8086' }).Count) { throw 'Intel graphics not found. Check Device Manager first.' }
    $url = 'https://downloadmirror.intel.com/932449/gfx_win_101.9175.exe'
    $hash = 'c1c7a858a5c977df59a3b6352a925100fbf97199b235eb5c3e45a5d037850b363bbc7605206a85bc5dcaeac0c751a06875f91b9bc13b31e59115d784c9c14111'
    $algorithm = 'SHA512'
}
$file = Join-Path $env:TEMP ([IO.Path]::GetFileName($url))
Write-Host 'Downloading the WHQL driver. Complete any installation prompts and reboot afterwards.'
Invoke-WebRequest -Uri $url -OutFile $file
if ((Get-FileHash -LiteralPath $file -Algorithm $algorithm).Hash -ne $hash) { throw 'Graphics-driver checksum mismatch.' }
$p = Start-Process -FilePath $file -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Driver installer exited with $($p.ExitCode); check installer result before continuing." }
Write-Host 'Driver installer exited successfully. Reboot before the desktop stage, then verify driver functionality.'
