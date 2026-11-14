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
# BEGIN effective-model verification (safe mock tests execute this block)
# config set writes globally; config get returns the effective layered value.
# Never clear project, environment or runtime overrides to force our default.
try {
    $effectiveRaw = (& $omp config get modelRoles --json | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'OMP effective-role readback failed.' }
    $effective = $effectiveRaw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
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

