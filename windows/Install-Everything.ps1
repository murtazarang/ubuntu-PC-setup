# Everything 1.4 stable and its PowerToys Run plugin, using upstream WinGet instructions.
# https://github.com/lin-ycv/EverythingPowerToys/wiki
[CmdletBinding()]
param([string]$EverythingPath = '')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Get-Process -Name PowerToys,PowerToys.Settings -ErrorAction SilentlyContinue) {
    throw 'Exit PowerToys from its tray icon before installing the Everything plugin; no process was closed.'
}
foreach ($id in @('voidtools.Everything', 'lin-ycv.EverythingPowerToys')) {
    & winget.exe install --exact --id $id --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade
    $code = '0x{0:X8}' -f ([long]$LASTEXITCODE -band 0xFFFFFFFFL)
    if ($code -notin @('0x00000000','0x8A150061','0x8A15010D')) { throw "Installing $id failed ($code)." }
}
$plugin = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\PowerToys Run\Plugins\Everything'
$manifest = Join-Path $plugin 'plugin.json'
if (-not (Test-Path -LiteralPath $manifest)) { throw "Everything plugin manifest not found at $manifest." }
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
& $uv run --no-project python (Join-Path $PSScriptRoot 'configure_everything.py') --settings (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\PowerToys Run\settings.json') --manifest $manifest
if ($LASTEXITCODE -ne 0) { throw 'Everything plugin validation/settings merge failed.' }

. (Join-Path $PSScriptRoot 'Find-DesktopExecutable.ps1')
$candidates = @((Join-Path $env:ProgramFiles 'Everything\Everything.exe'), (Join-Path $env:LOCALAPPDATA 'Everything\Everything.exe'))
if (${env:ProgramFiles(x86)}) { $candidates += Join-Path ${env:ProgramFiles(x86)} 'Everything\Everything.exe' }
$exe = Find-DesktopExecutable -Name 'Everything.exe' -Fallbacks $candidates -ExplicitPath $EverythingPath
# Official options; no indexing filters or user preferences are replaced.
# https://www.voidtools.com/support/everything/command_line_options/
if (-not (Get-Service -Name Everything -ErrorAction SilentlyContinue)) {
    $p = Start-Process -FilePath $exe -ArgumentList '-install-service' -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw 'Everything service installation failed.' }
}
Start-Service -Name Everything -ErrorAction Stop
$p = Start-Process -FilePath $exe -ArgumentList '-install-run-on-system-startup' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw 'Everything startup registration failed.' }
Start-Process -FilePath $exe -ArgumentList '-startup'
Write-Host 'Everything and the PowerToys Run plugin are installed. Allow initial indexing, then test a known filename in Win+F2.'
