# Execute only Setup.ps1's PATH merge block. No installer or registry write runs.
$ErrorActionPreference = 'Stop'
$setup = Join-Path (Split-Path $PSScriptRoot -Parent) 'Setup.ps1'
$source = Get-Content -LiteralPath $setup -Raw
$start = $source.IndexOf('# Refresh persisted paths')
$end = $source.IndexOf("& (Join-Path `$PSScriptRoot 'Install-OMP.ps1')", $start)
if ($start -lt 0 -or $end -le $start) { throw 'PATH merge block not found.' }
$merge = [scriptblock]::Create($source.Substring($start, $end - $start))
$originalPath = $env:Path
try {
    $env:Path = 'C:\process-only-first;C:\process-only-second'
    & $merge
    $firstPass = $env:Path
    if (-not $firstPass.StartsWith('C:\process-only-first;C:\process-only-second;')) {
        throw 'Process PATH entries or their precedence were lost.'
    }
    foreach ($expected in @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'),
        (Join-Path $env:USERPROFILE '.local\bin')
    )) {
        if ($expected -notin ($env:Path -split ';')) { throw "Missing required PATH entry: $expected" }
    }
    & $merge
    if ($env:Path -ne $firstPass) { throw 'Repeating PATH merge changed or duplicated entries.' }
} finally { $env:Path = $originalPath }
Write-Host 'PATH preservation, required entries and rerun checks passed; only process environment was changed and restored.'
