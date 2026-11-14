# Run from Windows PowerShell or PowerShell 7 under the account being configured.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This script requires native Windows.' }
if ($PSVersionTable.PSVersion.Major -lt 7) {
    & winget.exe install --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity
    $code = [long]$LASTEXITCODE -band 0xffffffff
    if ($code -ne 0 -and $code -ne 0x8A15002B) { throw "PowerShell installation failed: $code" }
}
Write-Host 'Open PowerShell 7 as administrator, change into this Windows folder, and run Setup.ps1 as described in README.md.'
