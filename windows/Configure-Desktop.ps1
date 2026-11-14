# Configure native Windows equivalents to the requested GNOME utilities.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$registry = 'HKCU:\Software\Microsoft\Clipboard'
New-Item -Path $registry -Force | Out-Null
New-ItemProperty -Path $registry -Name 'EnableClipboardHistory' -Value 1 -PropertyType DWord -Force | Out-Null

$dscCandidates = @(
    (Join-Path $env:ProgramFiles 'PowerToys\PowerToys.DSC.exe'),
    (Join-Path $env:LOCALAPPDATA 'PowerToys\PowerToys.DSC.exe')
)
$dsc = $dscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $dsc) { throw 'PowerToys DSC not found; install PowerToys and retry.' }
$base = Split-Path -Parent $dsc
$settingsCli = Join-Path $base 'bin\PowerToys.Settings.CLI.exe'
$runner = Join-Path $base 'PowerToys.exe'
if (-not (Test-Path -LiteralPath $settingsCli)) { throw 'PowerToys Settings CLI not found.' }
if (Get-Process -Name PowerToys -ErrorAction SilentlyContinue) {
    throw 'Close PowerToys before configuring its utilities, then rerun the Desktop stage.'
}
foreach ($module in @('PowerLauncher','Awake')) {
    & $settingsCli enable $module
    if ($LASTEXITCODE -ne 0) { throw "Could not enable PowerToys module $module." }
}
# Get and modify the complete current configuration rather than replacing other settings.
$existing = (& $dsc get --resource settings --module PowerLauncher | Out-String | ConvertFrom-Json -AsHashtable)
if ($LASTEXITCODE -ne 0 -or -not $existing.settings.properties) { throw 'Could not read PowerToys Run settings.' }
$existing.settings.properties.open_powerlauncher = @{ win=$true; alt=$false; ctrl=$false; shift=$false; code=113 }
$payload = ConvertTo-Json -InputObject $existing -Compress -Depth 50
& $dsc set --resource settings --module PowerLauncher --input $payload
if ($LASTEXITCODE -ne 0) { throw 'Could not configure PowerToys Run Win+F2.' }
if (Test-Path -LiteralPath $runner) { Start-Process -FilePath $runner }
Write-Host 'Configured Windows clipboard history (Win+V) and PowerToys Run Win+F2.'
Write-Host 'PowerToys Awake supplies the on-demand keep-awake control; enable it in PowerToys if needed.'
