#Requires -Version 5.1
# Existing-install entry point. Canonical install.ps1 performs the migration.
& {
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'),
    [ValidateSet(0,90,180,270)][int]$Rotation = 270
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'portrait.yaml')) -and
    -not (Test-Path -LiteralPath (Join-Path $env:ProgramFiles 'AX206Panel\current.json'))) {
    throw 'No existing AX206 installation found. Use install.ps1 for a fresh installation.'
}
$content = Invoke-RestMethod 'https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1'
if ($content -isnot [string] -or $content -notmatch '^#Requires -Version 5\.1') { throw 'GitHub did not return the expected PowerShell launcher. Nothing was executed.' }
$options = @{InstallDir=$InstallDir}
if ($PSBoundParameters.ContainsKey('Rotation')) { $options.Rotation=$Rotation }
& ([scriptblock]::Create($content)) @options
} @args
