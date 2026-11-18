#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Status','Info','Sensors','TestPattern','Preview')][string]$Action = 'Status',
    [ValidateRange(0,99)][int]$Index = 0
)
$ErrorActionPreference = 'Stop'
$config = & {
    param($Helper,$ManagedRoot)
    . $Helper -FunctionsOnly
    Read-ServiceConfig $ManagedRoot
} (Join-Path $PSScriptRoot 'Service.ps1') (Join-Path $env:ProgramFiles 'AX206Panel')
$dir = $config.release
$python = Join-Path $dir '.venv\Scripts\python.exe'
if ($Action -eq 'Status') {
    & (Join-Path $dir 'Service.ps1') -Action Status
    return
}
if ($Action -in @('Info','TestPattern') -and (Get-Service AX206Panel).Status -ne 'Stopped') {
    throw 'Stop the AX206Panel service before USB diagnostics so two processes do not claim the display. Restart it afterwards.'
}
$oldDll = $env:AX206_LHM_DLL
try {
    $env:AX206_LHM_DLL = Join-Path $dir 'source\lib\LibreHardwareMonitorLib.dll'
    switch ($Action) {
        'Info' { & $python -E -s -m ax206panel --info --index $Index }
        'Sensors' { & $python -E -s -m ax206panel --list-sensors }
        'TestPattern' { & $python -E -s -m ax206panel --test-pattern --index $Index }
        'Preview' { & $python -E -s (Join-Path $dir 'panel.py') --preview (Join-Path $env:TEMP 'ax206-preview.png') }
    }
    if ($LASTEXITCODE -ne 0) { throw "AX206 $Action failed with exit code $LASTEXITCODE." }
} finally { $env:AX206_LHM_DLL = $oldDll }
