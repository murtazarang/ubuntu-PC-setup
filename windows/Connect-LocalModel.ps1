# Connect OMP to an already running Strata or XeStrata endpoint.
[CmdletBinding()]
param([ValidateSet('8080', '8095')][string]$Port = '8080')
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$omp = (Get-Command omp.exe -CommandType Application -ErrorAction Stop).Source
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
$agentDir = (& $omp config path | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $agentDir) { throw 'Could not locate OMP configuration.' }

$selector = (& $uv run --no-project --with PyYAML python (Join-Path $PSScriptRoot 'configure_model.py') --agent-dir $agentDir --port $Port | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $selector.StartsWith('local-inference/')) {
    throw 'Could not read the local model endpoint or update OMP models.'
}
$current = (& $omp config get modelRoles --json | Out-String | ConvertFrom-Json -AsHashtable)
if ($LASTEXITCODE -ne 0) { throw 'Could not read OMP roles.' }
$roles = $current.value
if ($roles -isnot [System.Collections.IDictionary]) { throw 'OMP model roles are not a mapping.' }
$roles.default = $selector
$encoded = ConvertTo-Json -InputObject $roles -Compress -Depth 20
& $omp config set modelRoles $encoded
if ($LASTEXITCODE -ne 0) { throw 'Could not set the default OMP model.' }
Write-Host "OMP default model: $selector (127.0.0.1:$Port)"
