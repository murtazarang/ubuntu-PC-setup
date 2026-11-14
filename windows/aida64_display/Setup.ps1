#Requires -Version 5.1
[CmdletBinding()]
param([string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'))
$ErrorActionPreference = 'Stop'
$commit = '11280756789f1d61b80b49383b255acde62a9c60'
$uv = Get-Command uv.exe -ErrorAction SilentlyContinue
if (-not $uv) { throw 'uv is required. Run the existing PC setup prerequisites, or install uv from https://docs.astral.sh/uv/getting-started/installation/ and reopen PowerShell.' }
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
$source = Join-Path $InstallDir "win-ax206-display-$commit"
if (-not (Test-Path -LiteralPath $source)) {
    $temp = Join-Path $env:TEMP ([guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        Write-Host 'Downloading the pinned AX206 application source...'
        Invoke-WebRequest "https://github.com/mechcow/win-ax206-display/archive/$commit.zip" -OutFile "$temp\source.zip" -UseBasicParsing
        Expand-Archive -LiteralPath "$temp\source.zip" -DestinationPath $temp
        Move-Item -LiteralPath "$temp\win-ax206-display-$commit" -Destination $source
    } finally { Remove-Item -LiteralPath $temp -Recurse -Force }
}
$python = Join-Path $InstallDir '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & $uv.Source venv --python 3.11 (Join-Path $InstallDir '.venv')
    if ($LASTEXITCODE -ne 0) { throw 'uv venv failed.' }
}
& $uv.Source pip install --python $python --editable $source
if ($LASTEXITCODE -ne 0) { throw 'AX206 dependencies failed to install.' }
$marker = Join-Path $source 'lib\setup-complete.txt'
if (-not (Test-Path -LiteralPath $marker) -or -not (Test-Path -LiteralPath (Join-Path $source 'lib\LibreHardwareMonitorLib.dll'))) {
    Write-Host 'Downloading LibreHardwareMonitor libraries from NuGet (PawnIO is not installed or changed)...'
    & $python (Join-Path $source 'tools\fetch_lhm.py')
    if ($LASTEXITCODE -ne 0) { throw 'LibreHardwareMonitor library download failed; rerun setup to retry.' }
    if (-not (Test-Path -LiteralPath (Join-Path $source 'lib\LibreHardwareMonitorLib.dll'))) { throw 'LibreHardwareMonitorLib.dll was not extracted. Setup incomplete.' }
    Set-Content -LiteralPath $marker -Value 'Completed fetch_lhm.py'
}
# Copy runner only. Never overwrite an existing user-customized theme.
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'panel.py') -Destination $InstallDir -Force
if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'portrait.yaml'))) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'portrait.yaml') -Destination $InstallDir
}
Write-Host "Installed at $InstallDir. No USB driver, PawnIO, startup task or other application was changed."
Write-Host 'Next: run .\Run.ps1 -Action Info, then .\Run.ps1 -Rotation 270 (or 90 if upside down).'
