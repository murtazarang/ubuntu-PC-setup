# Called only after current authenticated WebUI import+readback succeeds.
# Never deletes skill repos, .omp, chat/config data, or Wikipedia.
[CmdletBinding()]
param([switch]$MigrationVerifiedThisRun)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not $MigrationVerifiedThisRun){throw 'Complete Finish Open WebUI Setup first; cleanup requires successful migration in this run.'}
$directory=if($env:PI_INSTALL_DIR){$env:PI_INSTALL_DIR}else{Join-Path $env:LOCALAPPDATA 'omp'}
$directory=[IO.Path]::GetFullPath($directory).TrimEnd('\','/')
$binary=Join-Path $directory 'omp.exe'
if(-not(Test-Path -LiteralPath $binary -PathType Leaf)){Write-Host 'No official OMP binary installation found; other installation methods are untouched.';return}
$item=Get-Item -LiteralPath $binary -Force
if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'OMP executable is a link; preserving it.'}
function Assert-UnlinkedOMPAncestors {
$ancestor=Get-Item -LiteralPath $directory -Force
while($ancestor){
    if($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'OMP directory has a linked ancestor; preserving it.'}
    $ancestor=$ancestor.Parent
}
}
Assert-UnlinkedOMPAncestors
$originalHash=(Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash
foreach($process in @(Get-CimInstance Win32_Process -Filter "Name='omp.exe'")){
    if(-not $process.ExecutablePath){throw 'Cannot identify a running OMP process. Close OMP before cleanup.'}
    if([IO.Path]::GetFullPath($process.ExecutablePath) -ieq $binary){throw 'Close OMP before cleanup. No process was terminated.'}
}
Write-Host "Skills and connections were verified in Open WebUI. Permanently remove this old program file: $binary"
Write-Host 'Its exact user PATH directory entry will also be removed. All old skills, settings and corpus files remain.'
$answer=Read-Host 'Type DELETE to confirm, or Enter to keep it'
if($answer -cne 'DELETE'){Write-Host 'OMP program retained.';return}
# Recheck parent links and content after confirmation, not just size/timestamp.
Assert-UnlinkedOMPAncestors
$current=Get-Item -LiteralPath $binary -Force
if(($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $current.Length -ne $item.Length -or $current.LastWriteTimeUtc -ne $item.LastWriteTimeUtc){throw 'OMP changed during confirmation; preserved.'}
if((Get-FileHash -LiteralPath $binary -Algorithm SHA256).Hash -ne $originalHash){throw 'OMP content changed during confirmation; preserved.'}
Remove-Item -LiteralPath $binary -Force
$path=[Environment]::GetEnvironmentVariable('Path','User')
$kept=@($path -split ';'|Where-Object {
    if(-not $_){$true}else{
        try {[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($_.Trim('"'))).TrimEnd('\','/') -ine $directory}catch{$true}
    }
})
[Environment]::SetEnvironmentVariable('Path',($kept -join ';'),'User')
Write-Host 'Removed old OMP executable and its exact user PATH entry. Skills/configuration/Wikipedia remain.'
