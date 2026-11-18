# Actual deletion only inside disposable fixtures. Never user data.
$ErrorActionPreference='Stop'
$target=Join-Path $PSScriptRoot 'Remove-OldSkillCollections.ps1'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('old-skills-test-'+[guid]::NewGuid())
$old=@{};foreach($key in @('LOCALAPPDATA','APPDATA','USERPROFILE','PI_CONFIG_FILES','PI_CONFIG_DIR','PI_CODING_AGENT_DIR','PASEO_HOME','PASEO_ELECTRON_USER_DATA_DIR','STRATA_SETTINGS_FILE')){$old[$key]=[Environment]::GetEnvironmentVariable($key)}
$global:OldSkillsFixture=@{Unknown=$false;Processes=@();InjectArchive='';Answer='';Targets=[Collections.Generic.Queue[string]]::new()}
function global:Get-Command {param($Name,$CommandType,$ErrorAction) if($Name -eq 'uv.exe'){return [pscustomobject]@{Source='Invoke-OldSkillsFixtureUv'}};throw "Unexpected tool: $Name"}
function global:Invoke-OldSkillsFixtureUv {
    $global:LASTEXITCODE=0
    if($args[0] -ne 'run' -or $args -notcontains '--with' -or $args -notcontains 'PyYAML' -or $args -notcontains '--root'){throw 'Unexpected inventory command'}
    if($global:OldSkillsFixture.Unknown){'{"custom_roots":["C:\\shared-custom-skills"]}'}else{'{"custom_roots":[]}'}
}
function global:Get-CimInstance {param($ClassName) return $global:OldSkillsFixture.Processes}
function global:Read-Host {param($Prompt) if($global:OldSkillsFixture.InjectArchive){Set-Content $global:OldSkillsFixture.InjectArchive 'appeared during confirmation'}; if($global:OldSkillsFixture.Answer -eq 'paths'){return $global:OldSkillsFixture.Targets.Dequeue()};return ''}
try {
    $env:LOCALAPPDATA=Join-Path $temp 'local';$env:APPDATA=Join-Path $temp 'roaming';$env:USERPROFILE=Join-Path $temp 'user'
    foreach($key in @('PI_CONFIG_FILES','PI_CONFIG_DIR','PI_CODING_AGENT_DIR','PASEO_HOME','PASEO_ELECTRON_USER_DATA_DIR','STRATA_SETTINGS_FILE')){[Environment]::SetEnvironmentVariable($key,$null,'Process')}
    $protected=Join-Path $temp 'wiki';New-Item -ItemType Directory $protected -Force|Out-Null
    Set-Content (Join-Path $protected 'archive.zim') 'retain'
    $parent=Join-Path $env:LOCALAPPDATA 'OMP-Skills'
    $targets=@((Join-Path $parent 'scientific-agent-skills'),(Join-Path $parent 'claude-scientific-writer'),(Join-Path $parent 'education-agent-skills'),(Join-Path $env:USERPROFILE '.omp'),(Join-Path $env:USERPROFILE '.paseo'),(Join-Path $env:APPDATA 'Paseo'),(Join-Path $env:APPDATA 'Strata'),(Join-Path $env:APPDATA 'xestrata'))
    foreach($path in $targets){New-Item -ItemType Directory $path -Force|Out-Null;Set-Content (Join-Path $path 'custom-edits.txt') 'delete as explicitly requested'}
    Set-Content (Join-Path $parent 'unrelated.txt') 'retain'
    foreach($path in $targets){
        foreach($name in @('WIKIPEDIA.ZIM','wikipedia.ZIM.PART')){
            $nested=Join-Path $path 'nested';New-Item -ItemType Directory $nested -Force|Out-Null
            $archive=Join-Path $nested $name;Set-Content $archive 'retain unregistered archive'
            $blocked=$false;try{& $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected) -InventoryOnly}catch{$blocked=$true;if($_.Exception.Message -notlike "*$name*"){throw}}
            if(-not $blocked -or -not(Test-Path $archive)){throw 'Unregistered corpus must block all cleanup'}
            Remove-Item $archive
        }
    }
    $global:OldSkillsFixture.Unknown=$true
    $blocked=$false;try{& $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected) -InventoryOnly}catch{$blocked=$true}
    if(-not $blocked -or -not(Test-Path $targets[0])){throw 'Unknown shared custom skill root must stop preflight'}
    $global:OldSkillsFixture.Unknown=$false
    foreach($process in @([pscustomobject]@{Name='bun.exe';CommandLine='bun C:\tools\node_modules\@oh-my-pi\pi-coding-agent\dist\cli.js'},[pscustomobject]@{Name='node.exe';CommandLine=$null})){
        $global:OldSkillsFixture.Processes=@($process)
        $blocked=$false;try{& $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected) -InventoryOnly}catch{$blocked=$true}
        if(-not $blocked -or -not(Test-Path $targets[0])){throw 'Running or unreadable OMP runtime must block before old data deletion'}
    }
    $global:OldSkillsFixture.Processes=@()
    & $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected) -InventoryOnly
    $blocked=$false;try{& $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected)}catch{$blocked=$true}
    if(-not $blocked -or -not(Test-Path $targets[0])){throw 'Decline must preserve old data'}
    $blocked=$false;try{& $target -CleanupAuthorizedThisRun -ProtectedPaths @($targets[0]) -InventoryOnly}catch{$blocked=$true}
    if(-not $blocked){throw 'Active protected data overlap must block cleanup'}
    $appeared=Join-Path $targets[-1] 'late.zim.part'
    $global:OldSkillsFixture.InjectArchive=$appeared
    $global:OldSkillsFixture.Targets.Enqueue($targets[0]);$global:OldSkillsFixture.Answer='paths'
    $blocked=$false;try{& $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected)}catch{$blocked=$true}
    if(-not $blocked -or -not(Test-Path $targets[0]) -or -not(Test-Path $appeared)){throw 'Corpus appearing during confirmation must block even the first deletion'}
    $global:OldSkillsFixture.InjectArchive='';Remove-Item $appeared
    foreach($path in $targets){$global:OldSkillsFixture.Targets.Enqueue($path)}
    $global:OldSkillsFixture.Answer='paths'
    & $target -CleanupAuthorizedThisRun -ProtectedPaths @($protected)
    foreach($path in $targets){if(Test-Path $path){throw "Identified old data retained: $path"}}
    if(-not(Test-Path (Join-Path $parent 'unrelated.txt')) -or -not(Test-Path (Join-Path $protected 'archive.zim'))){throw 'Unrelated data/Wikipedia was removed'}
    Write-Host 'Old data fixture passed: edited collections/data deleted only after path confirmation; unknown shared roots, decline, protected overlap and Wikipedia preservation checked.'
}finally{
    foreach($key in $old.Keys){[Environment]::SetEnvironmentVariable($key,$old[$key],'Process')}
    foreach($name in @('Get-Command','Invoke-OldSkillsFixtureUv','Get-CimInstance','Read-Host')){Remove-Item ('Function:\'+$name) -ErrorAction SilentlyContinue}
    Remove-Variable OldSkillsFixture -Scope Global -ErrorAction SilentlyContinue
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
