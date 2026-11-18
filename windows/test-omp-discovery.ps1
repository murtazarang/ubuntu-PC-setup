# Safe wrapper fixtures: no real package manager, process, file removal or PATH write.
$ErrorActionPreference='Stop'
$target=Join-Path $PSScriptRoot 'Remove-VerifiedOMP.ps1'
$oldLocal=$env:LOCALAPPDATA;$oldOverride=$env:PI_INSTALL_DIR
$global:OMPDiscoveryFixture=@{}
function global:Get-Command {
    param($Name,$CommandType,[switch]$All,$ErrorAction)
    if($Name -eq 'npm.cmd'){if($global:OMPDiscoveryFixture.Npm){return [pscustomobject]@{Source='Invoke-FixtureNpm';CommandType='Application'}};return $null}
    if($Name -eq 'bun'){if($global:OMPDiscoveryFixture.Npm){return $null};return [pscustomobject]@{Source='Invoke-FixtureBun';CommandType='Application'}}
    if($global:OMPDiscoveryFixture.Unknown){return [pscustomobject]@{Source='C:\unexpected\omp.exe';CommandType='Application'}}
    if($global:OMPDiscoveryFixture.Installed){$bin=if($global:OMPDiscoveryFixture.Npm){'npm'}else{'bun'};return [pscustomobject]@{Source="C:\fixture\$bin\omp.exe";CommandType='Application'}}
    return @()
}
function global:Invoke-FixtureBun {
    $global:LASTEXITCODE=0
    if(($args -join '|') -eq 'pm|ls|--global'){
        if($global:OMPDiscoveryFixture.Installed){'@oh-my-pi/pi-coding-agent@20.0.0'}
        return
    }
    if(($args -join '|') -eq 'pm|bin|--global'){'C:\fixture\bun';return}
    if(($args -join '|') -eq 'remove|--global|@oh-my-pi/pi-coding-agent'){
        $global:OMPDiscoveryFixture.Removed++
        $global:OMPDiscoveryFixture.Installed=$false
        return
    }
    throw "Unexpected package-manager command: $args"
}
function global:Get-CimInstance { param($ClassName,$Filter) if($global:OMPDiscoveryFixture.Running){return [pscustomobject]@{Name='omp.exe';CommandLine='omp.exe'}};return @() }
function global:Read-Host { param($Prompt) if($global:OMPDiscoveryFixture.StartDuringPrompt){$global:OMPDiscoveryFixture.Running=$true};return $global:OMPDiscoveryFixture.Answer }
function global:Test-Path { param($LiteralPath,$PathType) return ($LiteralPath -eq 'C:\fixture\npm\node_modules') }
function global:Get-Content {param($LiteralPath,[switch]$Raw) if($global:OMPDiscoveryFixture.BadName){'{"name":"unrelated"}'}else{'{"name":"@oh-my-pi/pi-coding-agent"}'}}
function global:Invoke-FixtureNpm {
    $global:LASTEXITCODE=0
    switch ($args -join '|') {
        'root|--global' {'C:\fixture\npm\node_modules';return}
        'prefix|--global' {'C:\fixture\npm';return}
        'ls|--global|--depth=0|--json|@oh-my-pi/pi-coding-agent' {
            if($global:OMPDiscoveryFixture.Installed){'{"dependencies":{"@oh-my-pi/pi-coding-agent":{"version":"fixture"}}}'}else{$global:LASTEXITCODE=1;'{"name":"global"}'};return
        }
        'uninstall|--global|--ignore-scripts|@oh-my-pi/pi-coding-agent' {$global:OMPDiscoveryFixture.Removed++;$global:OMPDiscoveryFixture.Installed=$false;return}
        default {throw "Unexpected npm args: $args"}
    }
}

try {
    $env:LOCALAPPDATA='C:\fixture';$env:PI_INSTALL_DIR=''
    foreach($case in @('unknown','decline','success','race','npm-success','npm-bad-name','npm-race')){
        $global:OMPDiscoveryFixture=@{Npm=($case -like 'npm-*');BadName=($case -eq 'npm-bad-name');Running=$false;StartDuringPrompt=($case -like '*race');Unknown=($case -eq 'unknown');Installed=$true;Removed=0;Answer=$(if($case -eq 'decline'){''}else{'@oh-my-pi/pi-coding-agent'})}
        $failure=$null
        try {& $target -MigrationVerifiedThisRun}catch{$failure=$_}
        if($case -in @('success','npm-success')){
            if($failure -or $global:OMPDiscoveryFixture.Removed -ne 1){throw "Bun successful fixture failed: $failure"}
        }else{
            if(-not $failure -or $global:OMPDiscoveryFixture.Removed -ne 0){throw "$case must stop before package removal"}
        }
    }
    Write-Host 'OMP discovery wrapper tests passed: unknown stop, decline stop, exact Bun uninstall and absence verification.'
}finally{
    $env:LOCALAPPDATA=$oldLocal;$env:PI_INSTALL_DIR=$oldOverride
    foreach($name in @('Get-Command','Invoke-FixtureBun','Read-Host','Test-Path','Get-CimInstance','Get-Content','Invoke-FixtureNpm')){Remove-Item ('Function:\'+$name) -ErrorAction SilentlyContinue}
    Remove-Variable OMPDiscoveryFixture -Scope Global -ErrorAction SilentlyContinue
}
