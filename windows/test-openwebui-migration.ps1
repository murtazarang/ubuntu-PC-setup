# Safe actual entrypoint fixtures: disposable fake OMP files, never real programs.
$ErrorActionPreference='Stop'
$source=$PSScriptRoot
$temp=Join-Path ([IO.Path]::GetTempPath()) ('webui-migration-test-'+[guid]::NewGuid())
New-Item -ItemType Directory $temp|Out-Null
$oldDirectory=$env:PI_INSTALL_DIR
$oldPath=[Environment]::GetEnvironmentVariable('Path','User')
function global:Get-CimInstance { param($ClassName,$Filter) return @() }
if(Test-Path Variable:\global:WebUIMigrationFixtureState){throw 'Fixture state collision'}
$global:WebUIMigrationFixtureState=@{Action=$null;Answer=''}
function global:Read-Host { param($Prompt) if($global:WebUIMigrationFixtureState.Action){& $global:WebUIMigrationFixtureState.Action}; return $global:WebUIMigrationFixtureState.Answer }
try {
    $env:PI_INSTALL_DIR=Join-Path $temp 'omp'
    New-Item -ItemType Directory $env:PI_INSTALL_DIR|Out-Null
    $exe=Join-Path $env:PI_INSTALL_DIR 'omp.exe'
    Set-Content -LiteralPath $exe -Value 'test only; not executable'
    $keep=Join-Path $env:PI_INSTALL_DIR 'custom-skill.txt'
    Set-Content -LiteralPath $keep -Value 'must survive'
    $global:WebUIMigrationFixtureState.Answer=''
    & (Join-Path $source 'Remove-OMPBinary.ps1') -MigrationVerifiedThisRun
    if(-not(Test-Path $exe)){throw 'Decline incorrectly removed OMP'}
    $rejected=$false
    try { & (Join-Path $source 'Remove-OMPBinary.ps1') } catch {$rejected=$true}
    if(-not $rejected){throw 'Missing verification gate was accepted'}
    [Environment]::SetEnvironmentVariable('Path',($oldPath+';'+$env:PI_INSTALL_DIR+';'+$env:PI_INSTALL_DIR+'-unrelated'),'User')
    $global:WebUIMigrationFixtureState.Answer=$exe
    & (Join-Path $source 'Remove-OMPBinary.ps1') -MigrationVerifiedThisRun
    if(Test-Path $exe){throw 'Confirmed fake OMP file not removed'}
    if(-not(Test-Path $keep)){throw 'Unrelated file removed'}
    $after=[Environment]::GetEnvironmentVariable('Path','User') -split ';'
    if($env:PI_INSTALL_DIR -in $after){throw 'Exact PATH entry retained'}
    if(($env:PI_INSTALL_DIR+'-unrelated') -notin $after){throw 'Unrelated PATH entry removed'}
    # Content replacement with identical size and mtime must still be rejected.
    Set-Content -LiteralPath $exe -Value 'aaaa'
    $global:WebUIMigrationFixtureState.Action={
        $stamp=(Get-Item -LiteralPath $exe).LastWriteTimeUtc
        Set-Content -LiteralPath $exe -Value 'bbbb'
        (Get-Item -LiteralPath $exe).LastWriteTimeUtc=$stamp
    }.GetNewClosure()
    $rejected=$false
    try { & (Join-Path $source 'Remove-OMPBinary.ps1') -MigrationVerifiedThisRun } catch {$rejected=$true}
    $global:WebUIMigrationFixtureState.Action=$null
    if(-not $rejected -or -not(Test-Path $exe)){throw 'Same-size/mtime replacement was not preserved'}
    # Junction path is deliberately rejected even with confirmation.
    $linked=Join-Path $temp 'linked'
    New-Item -ItemType Junction -Path $linked -Target $env:PI_INSTALL_DIR|Out-Null
    Set-Content -LiteralPath $exe -Value 'fake'
    $env:PI_INSTALL_DIR=$linked
    $rejected=$false
    try { & (Join-Path $source 'Remove-OMPBinary.ps1') -MigrationVerifiedThisRun } catch {$rejected=$true}
    if(-not $rejected -or -not(Test-Path $exe)){throw 'Linked target guard failed'}
    [IO.Directory]::Delete($linked)
    $env:PI_INSTALL_DIR=Join-Path $temp 'omp'
    $originalDirectory=$env:PI_INSTALL_DIR
    $movedDirectory=Join-Path $temp 'original-omp'
    $global:WebUIMigrationFixtureState.Action={
        Move-Item -LiteralPath $originalDirectory -Destination $movedDirectory
        New-Item -ItemType Junction -Path $originalDirectory -Target $movedDirectory|Out-Null
    }.GetNewClosure()
    $rejected=$false
    try { & (Join-Path $source 'Remove-OMPBinary.ps1') -MigrationVerifiedThisRun } catch {$rejected=$true}
    $global:WebUIMigrationFixtureState.Action=$null
    if(-not $rejected -or -not(Test-Path (Join-Path $movedDirectory 'omp.exe'))){throw 'Ancestor swap during prompt was not preserved'}
    [IO.Directory]::Delete($originalDirectory)
    Move-Item -LiteralPath $movedDirectory -Destination $originalDirectory
    # Finish runs a real Python fixture, not an actual import/network operation.
    $root=Join-Path $temp 'webui'
    & python -m venv (Join-Path $root 'venv')
    if($LASTEXITCODE -ne 0){throw 'Python fixture creation failed'}
    $helper=Join-Path $root 'openwebui_skills.py'
    $cleanup=Join-Path $root 'Remove-VerifiedOMP.ps1'
    Set-Content -LiteralPath $cleanup -Value "Set-Content -LiteralPath (Join-Path `$PSScriptRoot 'cleaned') -Value yes"
    Set-Content -LiteralPath $helper -Value 'import sys; sys.exit(1)'
    $expectedFailurePreference=$ErrorActionPreference
    try {
        # Windows PowerShell 5.1 surfaces a child's expected stderr as NativeCommandError.
        $ErrorActionPreference='Continue'
        '' | & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'Finish-OpenWebUI.ps1') -Root $root 2>$null
        $expectedFailureExit=$LASTEXITCODE
    } finally {$ErrorActionPreference=$expectedFailurePreference}
    if($expectedFailureExit -ne 1){throw 'Finish failure did not return nonzero'}
    if(Test-Path (Join-Path $root 'cleaned')){throw 'Failed import triggered cleanup'}
    Set-Content -LiteralPath $helper -Value "import sys; assert '--reference-manifest' in sys.argv; assert '--wiki-key-file' in sys.argv"
    '' | & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'Finish-OpenWebUI.ps1') -Root $root
    if($LASTEXITCODE -ne 0){throw 'Finish successful fixture returned failure'}
    if(Test-Path (Join-Path $root 'cleaned')){throw 'Fresh Finish must never call legacy cleanup'}
    Write-Host 'PASS: decline/gate/exact path/preserved files/junction/import failure/manifest arguments.'
} finally {
    [Environment]::SetEnvironmentVariable('Path',$oldPath,'User')
    $env:PI_INSTALL_DIR=$oldDirectory
    Remove-Item Function:\Get-CimInstance -ErrorAction SilentlyContinue
    Remove-Item Function:\Read-Host -ErrorAction SilentlyContinue
    Remove-Variable -Name WebUIMigrationFixtureState -Scope Global -ErrorAction SilentlyContinue
    # Remove junction itself first; avoid traversing it during recursive fixture cleanup.
    foreach($candidate in @((Join-Path $temp 'linked'),(Join-Path $temp 'omp'))){
        if((Test-Path -LiteralPath $candidate) -and ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){[IO.Directory]::Delete($candidate)}
    }
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
