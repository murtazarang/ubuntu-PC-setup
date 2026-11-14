# No application is executed. Registry/PATH discovery is mocked; files are fixtures.
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'Find-DesktopExecutable.ps1')
$DiscoveryFixture = @{ Command = $null; Registered = $null }
function Get-Command { param($Name, $CommandType, $ErrorAction) $DiscoveryFixture.Command }
function Test-Path {
    param($LiteralPath, $PathType)
    if ($LiteralPath -like 'HK*:*') { return [bool]$DiscoveryFixture.Registered }
    Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType Leaf
}
function Get-Item {
    param($LiteralPath)
    $item = [pscustomobject]@{ Value = $DiscoveryFixture.Registered }
    $item | Add-Member -MemberType ScriptMethod -Name GetValue -Value { param($Name) $this.Value }
    return $item
}
$dir = Join-Path ([IO.Path]::GetTempPath()) ('desktop-discovery-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $exe = Join-Path $dir 'Everything.exe'
    New-Item -ItemType File -Path $exe | Out-Null
    $DiscoveryFixture.Command = [pscustomobject]@{ Source = $exe }
    if ((Find-DesktopExecutable -Name 'Everything.exe') -ne $exe) { throw 'PATH discovery failed' }
    $DiscoveryFixture.Command = $null
    $DiscoveryFixture.Registered = $exe
    if ((Find-DesktopExecutable -Name 'Everything.exe') -ne $exe) { throw 'App Paths discovery failed' }
    $DiscoveryFixture.Registered = $null
    if ((Find-DesktopExecutable -Name 'Everything.exe' -Fallbacks @($exe)) -ne $exe) { throw 'Fallback discovery failed' }
    if ((Find-DesktopExecutable -Name 'Everything.exe' -ExplicitPath $exe) -ne $exe) { throw 'Explicit discovery failed' }
    try { Find-DesktopExecutable -Name 'PowerToys.exe' -ExplicitPath $exe; throw 'Expected name rejection' }
    catch { if ($_.Exception.Message -notlike 'Expected an existing*') { throw } }
    try { Find-DesktopExecutable -Name 'Everything.exe'; throw 'Expected missing rejection' }
    catch { if ($_.Exception.Message -notlike 'Everything.exe not found*') { throw } }
    Write-Host 'Six desktop discovery fixture cases passed; no application was run.'
} finally { Remove-Item -LiteralPath $dir -Recurse -Force }
$global:LASTEXITCODE = 0
