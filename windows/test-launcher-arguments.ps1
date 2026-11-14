# Test downloaded-file invocation with explicit CLI options. Stop before OS/installer logic.
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'run.ps1')
$guard = "if (`$env:OS -ne 'Windows_NT') { throw 'This launcher requires Windows.' }"
if (-not $source.Contains($guard)) { throw 'Safe launcher boundary missing.' }
$source = $source.Replace($guard, '[pscustomobject]@{ Hardware = $Hardware; Stage = $Stage }; return')
$temp = Join-Path $env:TEMP ('launcher-arguments-' + [guid]::NewGuid().ToString() + '.ps1')
try {
    Set-Content -LiteralPath $temp -Value $source -Encoding UTF8
    $result = @(& $temp -Hardware Intel -Stage Desktop)
    if ($result.Count -ne 1 -or $result[0].Hardware -ne 'Intel' -or $result[0].Stage -ne 'Desktop') {
        throw 'Explicit launcher options were not forwarded correctly.'
    }
} finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
$global:LASTEXITCODE = 0
Write-Host 'Explicit launcher file arguments preserved; no installer ran.'
