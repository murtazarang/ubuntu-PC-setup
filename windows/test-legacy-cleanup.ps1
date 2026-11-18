$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1')
if (-not (Test-UnderPath 'C:\Apps\Strata\bin\strata.exe' 'C:\Apps\Strata')) { throw 'Child path not recognized.' }
if (Test-UnderPath 'C:\Apps\Strata-Other\bin\strata.exe' 'C:\Apps\Strata') { throw 'Sibling path falsely recognized.' }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('cleanup-test-'+[guid]::NewGuid())
New-Item -ItemType Directory $fixture | Out-Null
$oldLocal=$env:LOCALAPPDATA; $oldTemp=$env:TEMP; $oldOS=$env:OS
try {
    $env:LOCALAPPDATA=$fixture; $env:TEMP=$fixture; $env:OS='Windows_NT'
    $runtime=Join-Path $fixture 'Strata';$second=Join-Path $fixture 'XeStrata-Setup'
    New-Item -ItemType Directory $runtime | Out-Null
    New-Item -ItemType Directory (Join-Path $fixture 'Unrelated') | Out-Null
    Set-Content (Join-Path $fixture 'Unrelated\keep.txt') 'keep'
    $found=@(Get-LegacyCandidates)
    if ($found.Count -ne 1 -or $found[0].Path -ne $runtime) { throw 'Bad inventory scope.' }
    if ((Get-LocationDisposition (Join-Path $runtime 'Strata-data') $found) -notmatch 'permanent removal') { throw 'Nested model directory falsely reported retained.' }
    if ((Get-LocationDisposition (Join-Path $fixture 'Strata-other\model') $found) -notmatch 'retained') { throw 'Sibling external model falsely reported included.' }
    if ((Get-LocationDisposition 'relative-models' $found) -notmatch 'not resolved') { throw 'Relative path falsely guaranteed retained.' }
    function Get-PaseoRegistration { @() }
    function Show-ExternalLocations {}
    function Get-CimInstance { param($ClassName,$ErrorAction) @() }
    $script:configTouched=$false
    function Remove-StrataPathEntry { $script:configTouched=$true }
    function Remove-OldOmpProvider { $script:configTouched=$true }
    function Read-Host { param($Prompt) 'NO' }
    $Apply=$false
    $inventory=Invoke-LegacyCleanup 6>&1 | Out-String
    if (-not $inventory.Contains($runtime)) { throw 'Full literal removal path was not printed before confirmation.' }
    $Apply=$true
    Invoke-LegacyCleanup
    if (-not (Test-Path $runtime) -or $script:configTouched) { throw 'Dry-run or declined confirmation changed data/config.' }
    foreach($name in @('WIKIPEDIA.ZIM','wikipedia.ZIM.PART')){
        $nested=Join-Path $runtime 'nested';New-Item -ItemType Directory $nested -Force|Out-Null
        $archive=Join-Path $nested $name;Set-Content $archive 'unregistered corpus'
        $blocked=$false;try{Invoke-LegacyCleanup}catch{$blocked=$true;if($_.Exception.Message -notlike "*$name*"){throw}}
        if(-not $blocked -or -not(Test-Path $archive) -or $script:configTouched){throw 'Unregistered corpus must block all legacy modifications'}
        Remove-Item $archive
    }
    function Read-Host {param($Prompt) Set-Content (Join-Path $env:LOCALAPPDATA 'Strata\late.zim.part') 'arrived during prompt';'DELETE'}
    $blocked=$false;try{Invoke-LegacyCleanup}catch{$blocked=$true;if($_.Exception.Message -notmatch 'late.zim.part'){throw}}
    if(-not $blocked -or -not(Test-Path $runtime) -or $script:configTouched){throw 'Late corpus must block after confirmation'}
    Remove-Item (Join-Path $runtime 'late.zim.part')
    function Read-Host { param($Prompt) 'DELETE' }
    Invoke-LegacyCleanup
    if (Test-Path $runtime) { throw 'Runtime not deleted.' }
    if (Test-Path (Join-Path $fixture 'PC-Setup\LegacyAI-Quarantine')) { throw 'Direct removal created quarantine.' }
    if (-not (Test-Path (Join-Path $fixture 'Unrelated\keep.txt'))) { throw 'Unrelated file changed.' }
    Invoke-LegacyCleanup
    New-Item -ItemType Directory $runtime | Out-Null
    function Get-CimInstance { param($ClassName,$ErrorAction) if ($ClassName -eq 'Win32_Process') { [pscustomobject]@{ExecutablePath=(Join-Path $env:LOCALAPPDATA 'Strata\python.exe');ProcessId=999} } }
    $blocked=$false
    try { Invoke-LegacyCleanup } catch { if ($_.Exception.Message -match 'Close the old inference') {$blocked=$true} else {throw} }
    if (-not $blocked -or -not (Test-Path $runtime)) { throw 'Running process guard failed.' }
    function Get-CimInstance { param($ClassName,$ErrorAction) if ($ClassName -eq 'Win32_Service') { [pscustomobject]@{Name='FixtureService';PathName=(Join-Path $env:LOCALAPPDATA 'Strata\server.exe')} } }
    $blocked=$false
    try { Invoke-LegacyCleanup } catch { if ($_.Exception.Message -match 'FixtureService') {$blocked=$true} else {throw} }
    if (-not $blocked -or -not (Test-Path $runtime)) { throw 'Registered service guard failed.' }
    function Get-CimInstance { param($ClassName,$ErrorAction) @() }
    # A linked child to unrelated data must block before any deletion.
    $link=Join-Path $runtime 'unknown-link';$target=Join-Path $fixture 'Unrelated'
    $linkType=if ([IO.Path]::DirectorySeparatorChar -eq '\') {'Junction'} else {'SymbolicLink'}
    New-Item -ItemType $linkType -Path $link -Target $target | Out-Null
    try {
        $blocked=$false
        try { Invoke-LegacyCleanup } catch { if ($_.Exception.Message -match 'Refusing unexpected linked') {$blocked=$true} else {throw} }
        if (-not $blocked -or -not (Test-Path (Join-Path $target 'keep.txt'))) { throw 'Linked child guard failed.' }
    } finally { [IO.Directory]::Delete($link) }
    if ([IO.Path]::DirectorySeparatorChar -eq '\') {
        # The upstream Strata installer creates terminal/current as a junction.
        $terminal=Join-Path $runtime 'terminal';$version=Join-Path $terminal 'v1'
        New-Item -ItemType Directory $version -Force | Out-Null
        Set-Content (Join-Path $version 'fixture.txt') 'fixture'
        New-Item -ItemType Junction -Path (Join-Path $terminal 'current') -Target $version | Out-Null
        if (@(Get-SafeLegacyLinks $runtime).Count -ne 1) { throw 'Documented internal junction rejected.' }
        Invoke-LegacyCleanup
        if (Test-Path $runtime) { throw 'Documented Strata layout not removed.' }
        New-Item -ItemType Directory $runtime | Out-Null
    }
    New-Item -ItemType Directory $second | Out-Null
    function Remove-Item {
        param($LiteralPath,[switch]$Recurse,[switch]$Force,$ErrorAction)
        if ($LiteralPath -eq $second) { throw 'Injected second-delete failure' }
        Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Recurse:$Recurse -Force:$Force -ErrorAction Stop
    }
    $blocked=$false
    try { Invoke-LegacyCleanup } catch { if ($_.Exception.Message -match 'Already removed:.*Strata.*Injected second-delete failure') {$blocked=$true} else {throw} }
    if (-not $blocked -or (Test-Path $runtime) -or -not (Test-Path $second)) { throw 'Partial removal diagnostic/state incorrect.' }
    Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item
    Invoke-LegacyCleanup
    $archiveDir=Join-Path $fixture ('xestrata-'+[guid]::NewGuid())
    New-Item -ItemType Directory $archiveDir | Out-Null
    Set-Content (Join-Path $archiveDir 'XeStrata-1-windows-x64.7z') 'fixture'
    if (@(Get-LegacyCandidates | Where-Object Path -eq $archiveDir).Count -ne 1) { throw 'Recognized temporary archive missed.' }
    Set-Content (Join-Path $archiveDir 'unrelated.txt') 'keep'
    if (@(Get-LegacyCandidates | Where-Object Path -eq $archiveDir).Count -ne 0) { throw 'Mixed temporary directory must be retained.' }
    Write-Host 'Direct cleanup inventory, confirmation, scope, process/link guards, partial failure and rerun fixtures passed.'
} finally {
    if (Test-Path Function:\Remove-Item) { Microsoft.PowerShell.Management\Remove-Item Function:\Remove-Item }
    $env:LOCALAPPDATA=$oldLocal;$env:TEMP=$oldTemp;$env:OS=$oldOS
    Remove-Item -LiteralPath $fixture -Force -Recurse
}
