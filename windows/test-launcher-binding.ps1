# Execute launcher parameter binding in a safe harness; stop before any installation.
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'run.ps1')
$guard = "if ($env:OS -ne 'Windows_NT') { throw 'This launcher requires Windows.' }"
if (-not $source.Contains($guard)) { throw 'Launcher guard not found; test must be updated.' }
$source = $source.Replace($guard, "throw 'LAUNCHER_BINDING_TEST_REACHED'")
$Hardware = ''
$Stage = ''
try {
    Invoke-Expression $source
    throw 'Expected the test sentinel.'
} catch {
    if ($_.Exception.Message -ne 'LAUNCHER_BINDING_TEST_REACHED') { throw }
}
if ($Hardware -ne '' -or $Stage -ne '') { throw 'Launcher modified caller variables.' }
Write-Host 'Launcher reached safe sentinel with empty caller variables; no installer ran.'
