# Run from Windows PowerShell or PowerShell 7 under the account being configured.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This script requires native Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 7) {
    & winget.exe install --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade
    $code = '0x{0:X8}' -f ([long]$LASTEXITCODE -band 0xFFFFFFFFL)
    if ($code -notin @('0x00000000', '0x8A150061', '0x8A15010D')) { throw "PowerShell installation failed: $code" }
}
Write-Host 'Open PowerShell 7 as administrator, change into this Windows folder, and run Setup.ps1 as described in README.md.'
