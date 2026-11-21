# Retire only recognized PC Setup shortcuts and running text processes.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $Root -PathType Container)){return}
foreach($path in @($Root,(Join-Path $Root 'retired-shortcuts'),(Join-Path $Root 'processes.json'))){
    if(Test-Path -LiteralPath $path){
        $item=Get-Item -LiteralPath $path -Force
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Refusing linked old setup path: $path"}
    }
}
$desktop=[Environment]::GetFolderPath('DesktopDirectory')
$shortcut=$null
if($desktop){
    $path=Join-Path $desktop 'Colibri Serve.lnk'
    if(Test-Path -LiteralPath $path -PathType Leaf){
        $linked=(Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint
        if(-not $linked){
            $shell=New-Object -ComObject WScript.Shell
            $link=$shell.CreateShortcut($path)
            $expected=Join-Path $Root 'venv\Scripts\pythonw.exe'
            $arguments='"'+(Join-Path $Root 'openwebui_desktop.py')+'" text --root "'+$Root+'"'
            if($link.TargetPath -ieq $expected -and $link.Arguments -ceq $arguments -and $link.Description -ceq 'Ubuntu PC Setup local AI shortcut'){
                $shortcut=$path
            }
        }
        if(-not $shortcut){Write-Warning "Keeping unrecognized shortcut: $path"}
    }
}
$state=Join-Path $Root 'processes.json'
$python=Join-Path $Root 'venv\Scripts\python.exe'
$hasText=$false
if(Test-Path -LiteralPath $state -PathType Leaf){
    $record=Get-Content -LiteralPath $state -Raw | ConvertFrom-Json -AsHashtable
    if($record -isnot [System.Collections.IDictionary]){throw 'Unrecognized old process inventory. Nothing was stopped.'}
    $hasText=$record.Contains('model') -and $record['model'] -and $record['model']['kind'] -eq 'text'
}
if(-not $shortcut -and -not $hasText){return}
Write-Host 'Legacy text retirement stops only the recorded Colibri text model. Open WebUI, its image connection, models, history and Wikipedia are kept.'
if($shortcut){Write-Host "Archive setup-owned shortcut: $shortcut"}
if((Read-Host 'Type RETIRE TEXT to proceed, or Enter to keep old text launchers/processes') -cne 'RETIRE TEXT'){
    Write-Host 'Legacy text retirement skipped.'
    return
}
if(Test-Path -LiteralPath $state -PathType Leaf){
    if(-not(Test-Path -LiteralPath $python -PathType Leaf)){throw 'Old text process inventory exists, but its verifier Python is missing. Stop legacy processes manually before retiring these shortcuts.'}
    & $python -B (Join-Path $PSScriptRoot 'retire_legacy_text_windows.py') --root $Root
    if($LASTEXITCODE -ne 0){throw 'Could not retire old text processes safely. Old shortcuts and data kept.'}
}
if($shortcut){
    $backup=Join-Path (Join-Path $Root 'retired-shortcuts') ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $backup | Out-Null
    Move-Item -LiteralPath $shortcut -Destination $backup
    Write-Host "Old text shortcut archived in $backup. The Open WebUI, Colibri image and stop shortcuts remain."
}
