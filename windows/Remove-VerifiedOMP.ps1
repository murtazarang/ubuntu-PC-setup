# Explicit existing-PC cleanup: official OMP binary and Bun installs only.
[CmdletBinding()]
param([Alias('MigrationVerifiedThisRun')][switch]$CleanupAuthorizedThisRun,[switch]$InventoryOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $CleanupAuthorizedThisRun){throw 'Run the explicit existing-PC migration cleanup; runtime confirmation is required.'}
$oldOverride=$env:PI_INSTALL_DIR
$oldProcessPath=$env:Path
$package='@oh-my-pi/pi-coding-agent'
$directories=@((Join-Path $env:LOCALAPPDATA 'omp'))
if($oldOverride){$directories+=([IO.Path]::GetFullPath($oldOverride))}
$directories=@($directories|ForEach-Object {[IO.Path]::GetFullPath($_).TrimEnd('\','/')}|Select-Object -Unique)
$known=@($directories|ForEach-Object {Join-Path $_ 'omp.exe'})
$bun=Get-Command bun -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
$bunInstalled=$false
$bunBin=$null
if($bun){
    # Official Bun package manager commands; do not infer its global tree layout.
    $listing=(& $bun.Source pm ls --global 2>&1|Out-String)
    if($LASTEXITCODE -ne 0){throw 'Cannot inventory Bun global packages; no cleanup performed.'}
    $bunInstalled=$listing -match '@oh-my-pi/pi-coding-agent@'
    $bunBin=(& $bun.Source pm bin --global|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or -not $bunBin){throw 'Cannot identify Bun global executable directory; no cleanup performed.'}
    if($bunInstalled){foreach($name in @('omp','omp.exe','omp.cmd','omp.ps1')){$known+=Join-Path $bunBin $name}}
}
# npm places global Windows command shims directly in its configured prefix.
$npm=Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
$npmInstalled=$false
function Test-NpmOMPRegistration {
    $ErrorActionPreference='Continue'
    $raw=(& $npm.Source ls --global --depth=0 --json $package 2>$null|Out-String)
    $code=$LASTEXITCODE
    $data=$raw|ConvertFrom-Json -ErrorAction Stop
    if($code -notin @(0,1) -or $data.PSObject.Properties.Name -contains 'error'){throw 'npm global package inventory failed; no inferred removal.'}
    return (($data.PSObject.Properties.Name -contains 'dependencies') -and ($data.dependencies.PSObject.Properties.Name -contains $package))
}
if($npm){
    $npmRoot=(& $npm.Source root --global|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or -not $npmRoot){throw 'Cannot identify npm global package directory.'}
    $npmBin=(& $npm.Source prefix --global|Out-String).Trim()
    if($LASTEXITCODE -ne 0 -or -not $npmBin){throw 'Cannot identify npm global Windows executable directory.'}
    if(Test-Path -LiteralPath $npmRoot -PathType Container){$npmInstalled=Test-NpmOMPRegistration}
    if($npmInstalled){
        $metadata=Join-Path $npmRoot '@oh-my-pi\pi-coding-agent\package.json'
        $manifest=Get-Content -LiteralPath $metadata -Raw|ConvertFrom-Json
        if($manifest.name -cne $package){throw 'npm package metadata identity mismatch; preserved.'}
        foreach($name in @('omp','omp.exe','omp.cmd','omp.ps1')){$known+=Join-Path $npmBin $name}
    }
}
$commands=@(Get-Command omp,omp.exe,omp.cmd,omp.ps1 -All -ErrorAction SilentlyContinue)
foreach($command in $commands){
    if($command.CommandType -notin @('Application','ExternalScript') -or -not $command.Source -or [IO.Path]::GetFullPath($command.Source) -notin $known){
        throw "Unrecognized OMP installation/command preserved: $($command.Source) [$($command.CommandType)]. Remove it using its original package manager, then rerun."
    }
}
function Assert-NoRunningOMP([string]$Runtime){
    foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='omp.exe' OR Name='$Runtime'")){
        if($process.Name -ieq 'omp.exe' -or ($process.CommandLine -and $process.CommandLine -match '@oh-my-pi[\\/]pi-coding-agent')){throw 'Close the running OMP session before package removal. No process was terminated.'}
        if($process.Name -ieq $Runtime -and -not $process.CommandLine){throw "Cannot identify a running $Runtime process; no package removal attempted."}
    }
}
if($InventoryOnly){
    if($npmInstalled){Assert-NoRunningOMP 'node.exe'}
    if($bunInstalled){Assert-NoRunningOMP 'bun.exe'}
    if(@(Get-CimInstance Win32_Process -Filter "Name='omp.exe'").Count){throw 'Close OMP before cleanup; no process was terminated.'}
    Write-Host 'OMP installation inventory passed; no program was removed.'
    return
}
try {
    if($npmInstalled){
        Assert-NoRunningOMP 'node.exe'
        Write-Host "Remove only npm global package $package from $npmRoot. Node, other packages and source checkouts remain."
        if((Read-Host "Type $package to confirm, or Enter to retain") -cne $package){throw 'npm OMP removal declined; migration retained but uninstall incomplete.'}
        Assert-NoRunningOMP 'node.exe'
        $currentRoot=(& $npm.Source root --global|Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or $currentRoot -cne $npmRoot -or -not(Test-NpmOMPRegistration)){throw 'npm installation changed during confirmation; preserved.'}
        & $npm.Source uninstall --global --ignore-scripts $package
        if($LASTEXITCODE -ne 0 -or (Test-NpmOMPRegistration)){throw 'npm OMP uninstall did not verify.'}
    }
    if($bunInstalled){
        Assert-NoRunningOMP 'bun.exe'
        Write-Host "Remove the OMP package $package from Bun global installation ($bunBin). Bun and other packages remain."
        if((Read-Host "Type $package to confirm, or Enter to retain") -cne $package){throw 'OMP removal declined. Migration is retained, but uninstall is incomplete.'}
        Assert-NoRunningOMP 'bun.exe'
        $currentBin=(& $bun.Source pm bin --global|Out-String).Trim()
        if($LASTEXITCODE -ne 0 -or $currentBin -cne $bunBin){throw 'Bun global directory changed during confirmation; preserved.'}
        $currentList=(& $bun.Source pm ls --global|Out-String)
        if($LASTEXITCODE -ne 0 -or $currentList -notmatch '@oh-my-pi/pi-coding-agent@'){throw 'Bun package changed during confirmation; preserved.'}
        & $bun.Source remove --global $package
        if($LASTEXITCODE -ne 0){throw 'Bun OMP uninstall failed; no further cleanup attempted.'}
        $remaining=(& $bun.Source pm ls --global 2>&1|Out-String)
        if($LASTEXITCODE -ne 0 -or $remaining -match '@oh-my-pi/pi-coding-agent@'){throw 'Bun OMP removal did not verify.'}
    }
    foreach($directory in $directories){
        $binary=Join-Path $directory 'omp.exe'
        if(Test-Path -LiteralPath $binary -PathType Leaf){
            $env:PI_INSTALL_DIR=$directory
            & (Join-Path $PSScriptRoot 'Remove-OMPBinary.ps1') -CleanupAuthorizedThisRun
            if(Test-Path -LiteralPath $binary){throw "OMP program retained; uninstall incomplete: $binary"}
        }
    }
    # Check both current-session leftovers and the newly persisted PATH.
    $env:Path=([Environment]::GetEnvironmentVariable('Path','Machine')+';'+[Environment]::GetEnvironmentVariable('Path','User')+';'+$oldProcessPath)
    $remaining=@(Get-Command omp,omp.exe,omp.cmd,omp.ps1 -All -ErrorAction SilentlyContinue)
    if($remaining.Count){throw ('OMP still resolves after cleanup: '+(($remaining|ForEach-Object {$_.Source}) -join ', '))}
    Write-Host 'Verified no OMP command remains on current/persisted PATH. This program-only step did not remove shared Bun or additional user data.'
} finally {$env:PI_INSTALL_DIR=$oldOverride;$env:Path=$oldProcessPath}
