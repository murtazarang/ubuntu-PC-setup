# Safe delegation tests; no installations, services, downloads or USB operations.
$ErrorActionPreference='Stop'
$source=Get-Content (Join-Path $PSScriptRoot '..\Setup.ps1') -Raw
$source=$source.Replace("& (Join-Path `$PSScriptRoot 'Service.ps1')",'Invoke-FakeService')
function Invoke-FakeService { param($LegacyInstallDir,$Action,$Rotation) $script:Captured=$PSBoundParameters }
& ([scriptblock]::Create($source)) -InstallDir 'C:\path with spaces'
if ($script:Captured.LegacyInstallDir -ne 'C:\path with spaces' -or $script:Captured.Action -ne 'Install' -or $script:Captured.ContainsKey('Rotation')) {throw 'Canonical delegation or preservation failed'}
& ([scriptblock]::Create($source)) -Rotation 90
if ($script:Captured.Rotation -ne 90) {throw 'Explicit rotation lost'}
Write-Host 'PASS: setup canonical delegation and rotation preservation'
