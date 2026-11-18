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
if(-not $ArchiveDirectory){
    if(Test-Path -LiteralPath $reference){$ArchiveDirectory=[string](Get-Content -LiteralPath $reference -Raw|ConvertFrom-Json).archive_directory}
    else{$ArchiveDirectory=Join-Path $env:LOCALAPPDATA 'OpenZIM\archives'}
}
if(-not $ArchiveDirectory){throw 'Existing reference manifest has no archive directory; supply -ArchiveDirectory explicitly.'}
# BEGIN migration stages
& (Join-Path $PSScriptRoot 'Install-Reference.ps1') -ArchiveDirectory $ArchiveDirectory
& (Join-Path $PSScriptRoot 'Install-Colibri.ps1') -Hardware $Hardware -NoShortcut
& (Join-Path $PSScriptRoot 'Install-OpenWebUI.ps1')
foreach($file in @('Remove-VerifiedOMP.ps1','Remove-OMPBinary.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $root -Force}
$python=Join-Path $root 'venv\Scripts\python.exe'
& $python (Join-Path $root 'openwebui_desktop.py') ui --root $root
if($LASTEXITCODE -ne 0){throw 'Open WebUI did not start. Old software remains.'}
Write-Host 'Create your local Open WebUI account in the browser if this is its first launch. Existing accounts/settings remain.'
Read-Host 'Press Enter once your local account is ready; the next step verifies imports and Wikipedia before cleanup'
& $python (Join-Path $root 'openwebui_skills.py') import --root (Join-Path $root 'skill-repos') --url http://127.0.0.1:8080 --wiki-key-file (Join-Path $root 'wikipedia-api-key') --reference-manifest $reference
if($LASTEXITCODE -ne 0){throw 'Replacement skills/connections/archive verification failed. No legacy uninstall was started.'}
# Reject even confirmed legacy deletion when it overlaps active replacement data.
. (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1')
$legacyPaths=@(Get-LegacyCandidates|ForEach-Object {$_.Path})
$activeReference=Get-Content -LiteralPath $reference -Raw|ConvertFrom-Json
$activeColibri=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup\settings.json') -Raw|ConvertFrom-Json
$protected=@($root,[string]$activeReference.archive,[string]$activeReference.archive_directory,[string]$activeColibri.models,(Join-Path $env:LOCALAPPDATA 'OMP-Skills'),(Join-Path $env:USERPROFILE '.omp'))
$desktopConfig=Get-Content -LiteralPath (Join-Path $root 'desktop.json') -Raw|ConvertFrom-Json
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
# Preserve retired OMP settings: migration explicitly skips old provider edits.
& (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1') -Apply -RequireRemoval -SkipOmpConfig
& (Join-Path $root 'Remove-VerifiedOMP.ps1') -MigrationVerifiedThisRun
# END migration stages
Write-Host 'Existing-PC AI migration completed. Colibri/Open WebUI are ready; unrelated desktop applications/settings were not changed.'
