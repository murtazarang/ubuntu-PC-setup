# Migration-only deletion of the three old collection roots, including edits.
# Never called by fresh setup. Parent directory/unrelated siblings are retained.
[CmdletBinding()]
param([Alias('MigrationVerifiedThisRun')][switch]$CleanupAuthorizedThisRun,[Parameter(Mandatory=$true)][string[]]$ProtectedPaths,[switch]$InventoryOnly)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $CleanupAuthorizedThisRun){throw 'Use the explicit existing-PC migration cleanup; runtime confirmation is required.'}
if(-not $ProtectedPaths.Count){throw 'Active replacement/corpus protection paths are required.'}
$parent=Join-Path $env:LOCALAPPDATA 'OMP-Skills'
$defaults=@{
    PI_CONFIG_FILES=''
    PI_CONFIG_DIR='.omp'
    PI_CODING_AGENT_DIR=(Join-Path $env:USERPROFILE '.omp\agent')
    PASEO_HOME=(Join-Path $env:USERPROFILE '.paseo')
    PASEO_ELECTRON_USER_DATA_DIR=(Join-Path $env:APPDATA 'Paseo')
    STRATA_SETTINGS_FILE=(Join-Path $env:APPDATA 'Strata\settings.json')
}
foreach($key in $defaults.Keys){
    $value=[Environment]::GetEnvironmentVariable($key)
    if(-not $value){continue}
    $actual=$value;$expected=$defaults[$key]
    if($key -eq 'PI_CONFIG_DIR'){
        if([IO.Path]::IsPathRooted($actual)){throw "Nonstandard PI_CONFIG_DIR needs ownership review: $value"}
        $actual=Join-Path $env:USERPROFILE $actual
        $expected=Join-Path $env:USERPROFILE $expected
    }elseif($key -eq 'PASEO_HOME' -and ($actual -eq '~' -or $actual.StartsWith('~/') -or $actual.StartsWith('~\'))){
        $actual=Join-Path $env:USERPROFILE ($actual.Substring(1).TrimStart('/','\'))
    }
    if($key -ne 'PI_CONFIG_FILES' -and [IO.Path]::IsPathRooted($actual)){
        $actual=[IO.Path]::GetFullPath($actual).TrimEnd('/','\')
        $expected=[IO.Path]::GetFullPath($expected).TrimEnd('/','\')
    }
    if($actual -ine $expected){throw "Custom old application location needs ownership review before any deletion: $key=$value. No broad/shared directory is inferred to be disposable."}
}
$targets=@()
$identified=@(
    (Join-Path $parent 'scientific-agent-skills'),(Join-Path $parent 'claude-scientific-writer'),(Join-Path $parent 'education-agent-skills'),
    (Join-Path $env:USERPROFILE '.omp'),(Join-Path $env:USERPROFILE '.paseo'),
    (Join-Path $env:APPDATA 'Paseo'),(Join-Path $env:APPDATA 'Strata'),(Join-Path $env:APPDATA 'xestrata')
)
foreach($path in $identified){if(Test-Path -LiteralPath $path){$targets+=$path}}
# Read every owned profile configuration even if the old runtime was already removed.
$uv=Get-Command uv.exe -CommandType Application -ErrorAction Stop
$inventoryJson=(& $uv.Source run --no-project --with PyYAML python (Join-Path $PSScriptRoot 'inventory_old_omp_skills.py') --root (Join-Path $env:USERPROFILE '.omp')|Out-String)
if($LASTEXITCODE -ne 0){throw 'Stored OMP skill inventory failed; no old data was deleted.'}
$inventory=$inventoryJson|ConvertFrom-Json
foreach($value in @($inventory.custom_roots)){
    $full=[IO.Path]::GetFullPath([string]$value).TrimEnd('\','/')
    $covered=$false
    foreach($known in $identified){
        $knownFull=[IO.Path]::GetFullPath($known).TrimEnd('\','/')
        if($full.Equals($knownFull,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($knownFull+'\',[StringComparison]::OrdinalIgnoreCase)){$covered=$true;break}
    }
    if(-not $covered){throw "Additional configured OMP skill root requires exclusive-ownership review before deletion: $full. It may be shared with another tool; no unrelated directory was deleted."}
}
function Assert-SafeOldCollection([string]$Path){
    $item=Get-Item -LiteralPath $Path -Force
    if(-not $item.PSIsContainer){throw "Old collection path is not a directory: $Path"}
    $ancestor=$item
    while($ancestor){
        if($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Old collection uses linked path; preserved: $($ancestor.FullName)"}
        $ancestor=$ancestor.Parent
    }
    if(@(Get-ChildItem -LiteralPath $Path -Recurse -Force|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw "Old collection contains linked items; preserved: $Path"}
    & (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') -CandidatePaths @($Path) -ProtectedPaths $ProtectedPaths
}
function Assert-OldDataNotRunning {
    foreach($process in @(Get-CimInstance Win32_Process)){
        if($process.Name -in @('omp.exe','Paseo.exe')){throw 'Close OMP/Paseo before deleting their old data; no process was terminated.'}
        if($process.Name -in @('bun.exe','node.exe')){
            if(-not $process.CommandLine){throw 'Cannot determine ownership of a running Bun/Node process. Close it or make its command line readable before old-data cleanup.'}
            if($process.CommandLine -match '[\\/]@oh-my-pi[\\/]pi-coding-agent(?:[\\/\s]|$)'){throw 'Close the running OMP package before deleting old data; no process was terminated.'}
        }
        foreach($path in $targets){
            if($process.CommandLine -and $process.CommandLine.IndexOf($path,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "A running process references old app data: $path. Close it first."}
        }
    }
}
Assert-OldDataNotRunning
foreach($path in $targets){Assert-SafeOldCollection $path; Write-Host "Identified old app/skill data: $path"}
if($InventoryOnly){return}
foreach($path in $targets){
    Write-Warning "Permanently delete this identified OLD application/skill data directory, INCLUDING histories, settings, caches, local edits and custom additions inside it: $path"
    Write-Host 'Offline Wikipedia and any existing replacement collections remain. Unrelated siblings, active new-stack data and offline Wikipedia remain; identified old .omp/.paseo histories and settings ARE included in the listed directories.'
    $initial=Get-Item -LiteralPath $path -Force
    $created=$initial.CreationTimeUtc
    if((Read-Host 'Type the full directory path shown above to confirm irreversible removal; Enter cancels') -cne $path){throw "Old skill deletion declined. Collection retained: $path. Migration cleanup is incomplete."}
    Assert-OldDataNotRunning
    Assert-SafeOldCollection $path
    if((Get-Item -LiteralPath $path -Force).CreationTimeUtc -ne $created){throw 'Old collection directory changed during confirmation; preserved.'}
    Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    if(Test-Path -LiteralPath $path){throw "Old collection deletion did not verify: $path"}
    Write-Host "Deleted old collection: $path"
}
Write-Host 'Identified old application/skill data directories are absent. Parent/unrelated data and Wikipedia remain.'
