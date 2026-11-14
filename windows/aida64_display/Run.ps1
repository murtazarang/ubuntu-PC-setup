#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Panel','Info','Sensors','TestPattern','Preview')][string]$Action = 'Panel',
    [ValidateSet(0,90,180,270)][int]$Rotation = 270,
    [ValidateRange(0,99)][int]$Index = 0,
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel')
)
$ErrorActionPreference = 'Stop'
$python = Join-Path $InstallDir '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) { throw 'Run Setup.ps1 first.' }
switch ($Action) {
    'Info' { & $python -m ax206panel --info --index $Index }
    'Sensors' { & $python -m ax206panel --list-sensors }
    'TestPattern' { & $python -m ax206panel --test-pattern --index $Index }
    'Preview' { & $python (Join-Path $InstallDir 'panel.py') --preview (Join-Path $InstallDir 'preview.png') }
    'Panel' { & $python (Join-Path $InstallDir 'panel.py') --rotation $Rotation --index $Index }
}
if ($LASTEXITCODE -ne 0) { throw "AX206 $Action failed. Read the message above; no drivers or security settings were changed." }
