# Compatibility entry point; all new installations use Colibri, not Strata.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware)
& (Join-Path $PSScriptRoot 'Install-Colibri.ps1') -Hardware $Hardware
