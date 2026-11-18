#Requires -Version 5.1
[CmdletBinding()]
param(
    # Legacy folder is only an import source. Service code lives in Program Files.
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'),
    [ValidateSet(0,90,180,270)][int]$Rotation = 270
)
$ErrorActionPreference = 'Stop'
$options = @{LegacyInstallDir=$InstallDir;Action='Install'}
if ($PSBoundParameters.ContainsKey('Rotation')) { $options.Rotation=$Rotation }
& (Join-Path $PSScriptRoot 'Service.ps1') @options
