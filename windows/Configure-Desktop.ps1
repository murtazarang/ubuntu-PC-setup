# Configure native Windows equivalents to the requested GNOME utilities.
[CmdletBinding()]
param([string]$PowerToysPath = '', [string]$EverythingPath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$registry = 'HKCU:\Software\Microsoft\Clipboard'
New-Item -Path $registry -Force | Out-Null
New-ItemProperty -Path $registry -Name 'EnableClipboardHistory' -Value 1 -PropertyType DWord -Force | Out-Null

$candidates = @(
    (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.exe'),
    (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.exe')
)
if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'PowerToys\PowerToys.exe' }
. (Join-Path $PSScriptRoot 'Find-DesktopExecutable.ps1')
$runner = Find-DesktopExecutable -Name 'PowerToys.exe' -Fallbacks $candidates -ExplicitPath $PowerToysPath
$settings = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys'
# Let PowerToys write its own complete defaults before making a targeted merge.
if (-not (Test-Path -LiteralPath (Join-Path $settings 'settings.json'))) {
    Start-Process -FilePath $runner
    Read-Host 'Finish PowerToys first launch, exit PowerToys from its tray icon, then press Enter' | Out-Null
}
if (Get-Process -Name PowerToys,PowerToys.Settings -ErrorAction SilentlyContinue) {
    Read-Host 'Exit PowerToys and its Settings window, then press Enter to configure Win+F2' | Out-Null
}
if (Get-Process -Name PowerToys,PowerToys.Settings -ErrorAction SilentlyContinue) {
    throw 'PowerToys is still running; settings were not changed.'
}
# Merge source-defined JSON to retain existing plugin configuration and all
# unrelated settings; this path does not require enabling DSC.
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
& $uv run --no-project python (Join-Path $PSScriptRoot 'configure_powertoys.py') $settings
if ($LASTEXITCODE -ne 0) { throw 'PowerToys settings merge failed.' }
& (Join-Path $PSScriptRoot 'Install-Everything.ps1') -EverythingPath $EverythingPath
Start-Process -FilePath $runner
Write-Host 'Configured clipboard history (Win+V), PowerToys Run (Win+F2), and the Awake tray utility.'
Write-Host 'Awake is enabled; select a keep-awake duration from its tray menu when needed.'
