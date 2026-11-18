#Requires -Version 5.1
# Fresh installation and existing-install migration use the same service installer.
& {
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'),
    [ValidateSet(0,90,180,270)][int]$Rotation = 270
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Open PowerShell as administrator under your normal account.' }
if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) { throw 'uv is required. Install it using the PC setup prerequisites first.' }
$hostName = if ($PSVersionTable.PSEdition -eq 'Core') {'pwsh.exe'} else {'powershell.exe'}
$hostExe = Join-Path $PSHOME $hostName
$runDir = Join-Path $env:TEMP ('ax206-service-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $runDir | Out-Null
try {
    $archive = Join-Path $runDir 'setup.zip'
    Invoke-WebRequest 'https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip' -OutFile $archive -UseBasicParsing
    Expand-Archive -LiteralPath $archive -DestinationPath $runDir
    $scripts = Join-Path $runDir 'ubuntu-PC-setup-main\windows\aida64_display'
    foreach ($name in @('Setup.ps1','Service.ps1','Run.ps1','service_host.py','safe_theme.py','panel.py','lifecycle.py','usb_transport.py','portrait.yaml','LICENSE')) {
        if (-not (Test-Path -LiteralPath (Join-Path $scripts $name) -PathType Leaf)) { throw "Downloaded archive is missing AX206 file: $name" }
    }
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $scripts 'Setup.ps1'),'-InstallDir',$InstallDir)
    if ($PSBoundParameters.ContainsKey('Rotation')) { $arguments += @('-Rotation',[string]$Rotation) }
    & $hostExe @arguments
    if ($LASTEXITCODE -ne 0) { throw "AX206 service setup failed with exit code $LASTEXITCODE." }
    Write-Host 'Service setup complete. You can close this terminal.'
} catch {
    Write-Host "Downloaded setup files remain at $runDir"
    throw
}
} @args
