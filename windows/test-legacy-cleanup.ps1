$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1')
if (-not (Test-UnderPath 'C:\Apps\Strata\bin\strata.exe' 'C:\Apps\Strata')) { throw 'Child path not recognized.' }
if (Test-UnderPath 'C:\Apps\Strata-Other\bin\strata.exe' 'C:\Apps\Strata') { throw 'Sibling path falsely recognized.' }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('cleanup-test-'+[guid]::NewGuid())
New-Item -ItemType Directory $fixture | Out-Null
$oldLocal=$env:LOCALAPPDATA; $oldTemp=$env:TEMP; $oldOS=$env:OS
try {
    $env:LOCALAPPDATA=$fixture; $env:TEMP=$fixture; $env:OS='Windows_NT'
    New-Item -ItemType Directory (Join-Path $fixture 'Strata') | Out-Null
    New-Item -ItemType Directory (Join-Path $fixture 'Unrelated') | Out-Null
    Set-Content (Join-Path $fixture 'Unrelated\keep.txt') 'keep'
    $found=@(Get-LegacyCandidates)
    if ($found.Count -ne 1 -or $found[0].Path -ne (Join-Path $fixture 'Strata')) { throw 'Bad inventory scope.' }
    function Get-PaseoRegistration { @() }
    function Show-ExternalLocations {}
    function Get-CimInstance { param($ClassName,$ErrorAction) @() }
    function Remove-StrataPathEntry {}
    function Remove-OldOmpProvider {}
    $Apply=$false; $PurgeQuarantine=$false
    Invoke-LegacyCleanup
    if (-not (Test-Path (Join-Path $fixture 'Strata'))) { throw 'Dry-run changed data.' }
    $Apply=$true
    Invoke-LegacyCleanup
    if (Test-Path (Join-Path $fixture 'Strata')) { throw 'Runtime not quarantined.' }
    if (-not (Test-Path (Join-Path $fixture 'Unrelated\keep.txt'))) { throw 'Unrelated file changed.' }
    $manifests=@(Get-ChildItem (Join-Path $fixture 'PC-Setup\LegacyAI-Quarantine') -Filter manifest.json -Recurse)
    if ($manifests.Count -ne 1) { throw 'Missing restoration manifest.' }
    $record=Get-Content $manifests[0].FullName -Raw | ConvertFrom-Json
    if (-not (Test-Path $record[0].Quarantined)) { throw 'Quarantined data unavailable.' }
    Invoke-LegacyCleanup # idempotent, no second changes
    New-Item -ItemType Directory (Join-Path $fixture 'Strata') | Out-Null
    function Get-CimInstance { param($ClassName,$ErrorAction) if ($ClassName -eq 'Win32_Process') { [pscustomobject]@{ExecutablePath=(Join-Path $env:LOCALAPPDATA 'Strata\python.exe');ProcessId=999} } }
    $blocked=$false
    try { Invoke-LegacyCleanup } catch { if ($_.Exception.Message -match 'Close the old inference') {$blocked=$true} else {throw} }
    if (-not $blocked -or -not (Test-Path (Join-Path $fixture 'Strata'))) { throw 'Running process guard failed.' }
    function Get-CimInstance { param($ClassName,$ErrorAction) if ($ClassName -eq 'Win32_Process') { [pscustomobject]@{ExecutablePath='C:\OtherPython\python.exe';CommandLine=('python "'+(Join-Path $env:LOCALAPPDATA 'Strata\server.py')+'"');ProcessId=999} } }
    $blocked=$false
    try { Invoke-LegacyCleanup } catch { if ($_.Exception.Message -match 'Close the old inference') {$blocked=$true} else {throw} }
    if (-not $blocked) { throw 'External Python command-line guard failed.' }
    $archiveDir=Join-Path $fixture ('xestrata-'+[guid]::NewGuid())
    New-Item -ItemType Directory $archiveDir | Out-Null
    Set-Content (Join-Path $archiveDir 'XeStrata-1-windows-x64.7z') 'fixture'
    if (@(Get-LegacyCandidates | Where-Object Path -eq $archiveDir).Count -ne 1) { throw 'Recognized temporary archive missed.' }
    Set-Content (Join-Path $archiveDir 'unrelated.txt') 'keep'
    if (@(Get-LegacyCandidates | Where-Object Path -eq $archiveDir).Count -ne 0) { throw 'Mixed temporary directory must be retained.' }
    Write-Host 'Legacy cleanup dry-run, scope, quarantine, manifest, rerun and process guard tests passed.'
} finally { $env:LOCALAPPDATA=$oldLocal;$env:TEMP=$oldTemp;$env:OS=$oldOS;Remove-Item -LiteralPath $fixture -Force -Recurse }
