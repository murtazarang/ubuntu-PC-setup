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
# BEGIN global-model update (safe mock tests execute this block)
# Read only the saved global layer; never copy effective project roles globally.
# OMP commands/config.ts parses --scope; config-cli.ts handleListLayer omits unset keys.
$globalRaw = (& $omp config list --scope global --json | Out-String)
if ($LASTEXITCODE -ne 0) { throw 'Could not read global OMP roles.' }
$globalSettings = $globalRaw | ConvertFrom-Json -AsHashtable -NoEnumerate -ErrorAction Stop
if ($globalSettings -isnot [System.Collections.IDictionary]) { throw 'OMP global settings are not a mapping.' }
$roles = @{}
if ($globalSettings.Contains('modelRoles')) {
    $entry = $globalSettings['modelRoles']
    if ($entry -isnot [System.Collections.IDictionary] -or -not $entry.Contains('value') -or
        $entry['value'] -isnot [System.Collections.IDictionary]) {
        throw 'OMP global model roles are not a mapping; existing settings preserved.'
    }
    $roles = $entry['value']
}
$roles.default = $selector
$encoded = ConvertTo-Json -InputObject $roles -Compress -Depth 20
& $omp config set modelRoles $encoded
if ($LASTEXITCODE -ne 0) { throw 'Could not set the default OMP model.' }
# END global-model update
# BEGIN effective-model verification (safe mock tests execute this block)
# config set writes globally; config get returns the effective layered value.
# Never clear project, environment or runtime overrides to force our default.
try {
    $effectiveRaw = (& $omp config get modelRoles --json | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'OMP effective-role readback failed.' }
    $effective = $effectiveRaw | ConvertFrom-Json -AsHashtable -NoEnumerate -ErrorAction Stop
    if ($effective -isnot [System.Collections.IDictionary] -or
        $effective.value -isnot [System.Collections.IDictionary] -or
        -not $effective.value.Contains('default') -or
        $effective.value.default -isnot [string]) {
        throw 'OMP effective-role readback has an unexpected format.'
    }
    if ($effective.value.default -eq $selector) {
        Write-Host "OMP effective default model here: $selector (127.0.0.1:$Port). Other projects may override it."
    } else {
        Write-Warning "Saved global OMP model $selector, but the effective default here is '$($effective.value.default)'. Existing overrides were preserved; inspect OMP project/environment settings if you want this local model here."
    }
} catch {
    Write-Warning "Saved global OMP model $selector, but could not verify the effective default: $($_.Exception.Message) Existing overrides were preserved."
}
# END effective-model verification

