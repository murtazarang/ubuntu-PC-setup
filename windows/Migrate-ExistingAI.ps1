#Requires -Version 7.0
# Existing-PC AI migration only. Never runs Desktop/Apps/Drivers/Firefox setup.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,
      [string]$ArchiveDirectory)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'This migration is for native Windows.'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=[Security.Principal.WindowsPrincipal]::new($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw 'Use PowerShell as administrator under the existing user account.'}
foreach($tool in @('uv.exe','git.exe','curl.exe')){
    if(-not(Get-Command $tool -CommandType Application -ErrorAction SilentlyContinue)){throw "Existing setup prerequisite missing: $tool. Migration did not run unrelated system/application installers."}
}
$root=Join-Path $env:LOCALAPPDATA 'OpenWebUI-PC-Setup'
$reference=Join-Path $env:LOCALAPPDATA 'OpenZIM\reference.json'
if(Test-Path -LiteralPath $reference){
    $item=Get-Item -LiteralPath $reference -Force
    while($null -ne $item){
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Refusing linked Wikipedia reference: $($item.FullName). No cleanup started."}
        $item=if($item -is [IO.FileInfo]){$item.Directory}else{$item.Parent}
    }
    $record=Get-Content -LiteralPath $reference -Raw | ConvertFrom-Json
    if(-not $record.archive_directory -or -not $record.archive -or
       -not [IO.Path]::IsPathFullyQualified([string]$record.archive_directory) -or
       -not [IO.Path]::IsPathFullyQualified([string]$record.archive)){
        throw 'Existing Wikipedia manifest is invalid; no cleanup or download started.'
    }
    $savedArchive=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath([string]$record.archive_directory))
    $savedFile=[IO.Path]::GetFullPath([string]$record.archive)
    if($savedFile -ine (Join-Path $savedArchive 'wikipedia_en_all_nopic_2026-06.zim')){
        throw 'Existing Wikipedia manifest points to a different archive; no cleanup or download started.'
    }
    if($ArchiveDirectory -and [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($ArchiveDirectory)) -ine $savedArchive){
        throw 'Requested archive directory conflicts with the existing Wikipedia manifest; no cleanup or download started.'
    }
    $ArchiveDirectory=$savedArchive
}elseif(-not $ArchiveDirectory){
    $ArchiveDirectory=Join-Path $env:LOCALAPPDATA 'OpenZIM\archives'
}
if(-not [IO.Path]::IsPathFullyQualified($ArchiveDirectory)){throw 'Use an absolute Wikipedia archive path.'}
foreach($file in @('Install-HermesLocalAI.ps1','Retire-LegacyText.ps1','retire_legacy_text_windows.py')){
    if(-not(Test-Path -LiteralPath (Join-Path $PSScriptRoot $file) -PathType Leaf)){
        throw "Missing migration companion $file; no cleanup started."
    }
}
# BEGIN migration stages
# Reject even confirmed legacy deletion when it overlaps active replacement data.
. (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1')
$legacyCandidates=@(Get-LegacyCandidates)
$legacyPaths=@($legacyCandidates|ForEach-Object {$_.Path})
Assert-LegacyCorpusAbsent $legacyCandidates
$activeReference=if(Test-Path -LiteralPath $reference){Get-Content -LiteralPath $reference -Raw|ConvertFrom-Json}else{[pscustomobject]@{archive_directory=$ArchiveDirectory;archive=(Join-Path $ArchiveDirectory 'wikipedia_en_all_nopic_2026-06.zim')}}
$colibriSettings=Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup\settings.json'
$activeColibri=if(Test-Path -LiteralPath $colibriSettings){Get-Content -LiteralPath $colibriSettings -Raw|ConvertFrom-Json}else{[pscustomobject]@{models=(Join-Path $env:USERPROFILE 'colibri-models')}}
$protected=@($root,$ArchiveDirectory,(Join-Path $env:LOCALAPPDATA 'OpenZIM'),(Join-Path $env:USERPROFILE '.hermes'),(Join-Path $env:LOCALAPPDATA 'PCSetup\local-ai'),[string]$activeReference.archive,[string]$activeReference.archive_directory,[string]$activeColibri.models,(Join-Path $env:LOCALAPPDATA 'OMP-Skills'),(Join-Path $env:USERPROFILE '.omp'))
$desktopFile=Join-Path $root 'desktop.json'
$desktopConfig=if(Test-Path -LiteralPath $desktopFile){Get-Content -LiteralPath $desktopFile -Raw|ConvertFrom-Json}else{[pscustomobject]@{text_model=(Join-Path $activeColibri.models 'dense27b\model');image_model=(Join-Path $activeColibri.models 'qwen-image-2.1\model')}}
foreach($modelPath in @([string]$desktopConfig.text_model,[string]$desktopConfig.image_model)){
    if(-not $modelPath -or -not [IO.Path]::IsPathRooted($modelPath)){throw 'Active desktop model paths must be absolute before legacy cleanup.'}
    $protected+=$modelPath
    if(Test-Path -LiteralPath $modelPath -PathType Container){
        if(@(Get-ChildItem -LiteralPath $modelPath -Recurse -Force|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw "Active model contains linked files: $modelPath. Resolve their actual locations before legacy deletion."}
        $pointer=Join-Path $modelPath 'gguf.json'
        if(Test-Path -LiteralPath $pointer -PathType Leaf){
            $metadata=Get-Content -LiteralPath $pointer -Raw|ConvertFrom-Json
            if($metadata.format -ne 'colibri-gguf-v1'){throw 'Unknown GGUF reference format; legacy cleanup stopped.'}
            # Upstream gguf_import.py/resource_plan.py use these file fields; split shards share the GGUF parent.
            foreach($key in @('gguf','mtp','dspark','mmproj')){
                if($metadata.PSObject.Properties.Name -contains $key -and $metadata.$key){
                    $target=[string]$metadata.$key
                    if(-not [IO.Path]::IsPathRooted($target)){$target=Join-Path $modelPath $target}
                    $protected+=[IO.Path]::GetFullPath($target)
                    $protected+=Split-Path ([IO.Path]::GetFullPath($target)) -Parent
                }
            }
        }
    }
}
$protected+=Join-Path $root 'skill-repos'
if($desktopConfig.PSObject.Properties.Name -contains 'webui_environment'){
    foreach($key in @('HF_HOME','SENTENCE_TRANSFORMERS_HOME','TRANSFORMERS_CACHE','HF_HUB_CACHE')){
        if($desktopConfig.webui_environment.PSObject.Properties.Name -contains $key -and $desktopConfig.webui_environment.$key){$protected+=[string]$desktopConfig.webui_environment.$key}
    }
}

& (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') -CandidatePaths $legacyPaths -ProtectedPaths $protected
# Destructive-first order explicitly requested: preflight every known data path, then confirm each removal.
$oldCollections=Join-Path $env:LOCALAPPDATA 'OMP-Skills'
$oldOmpState=Join-Path $env:USERPROFILE '.omp'
$skillProtected=@($protected|Where-Object {$_ -ine $oldCollections -and $_ -ine $oldOmpState})
& (Join-Path $PSScriptRoot 'Remove-OldSkillCollections.ps1') -CleanupAuthorizedThisRun -ProtectedPaths $skillProtected -InventoryOnly
& (Join-Path $PSScriptRoot 'Remove-VerifiedOMP.ps1') -CleanupAuthorizedThisRun -InventoryOnly
& (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1') -Apply -RequireRemoval -SkipOmpConfig
& (Join-Path $PSScriptRoot 'Remove-OldSkillCollections.ps1') -CleanupAuthorizedThisRun -ProtectedPaths $skillProtected
& (Join-Path $PSScriptRoot 'Remove-VerifiedOMP.ps1') -CleanupAuthorizedThisRun
& (Join-Path $PSScriptRoot 'Install-HermesLocalAI.ps1') -Hardware $Hardware -ArchiveDirectory $ArchiveDirectory
& (Join-Path $PSScriptRoot 'Retire-LegacyText.ps1') -Root $root
# END migration stages
Write-Host 'Existing-PC AI migration finished. Colibri image serving and Open WebUI data were preserved.'
