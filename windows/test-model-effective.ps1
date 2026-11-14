# Safe: only executes the marked readback block; no endpoint, installer or config writes.
[CmdletBinding()]
param([string]$Source = (Join-Path $PSScriptRoot 'Connect-LocalModel.ps1'))
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText($Source)
$pattern = '(?s)# BEGIN effective-model verification.*?\r?\n(.*?)# END effective-model verification'
$match = [regex]::Match($text, $pattern)
if (-not $match.Success) { throw 'Effective-model verification block not found.' }
$block = [scriptblock]::Create($match.Groups[1].Value)
$selector = 'local-inference/desired'
$Port = '8080'
$omp = 'Invoke-MockOmp'
$fixture = @{ Mode = ''; Calls = 0 }
function Invoke-MockOmp {
    if (($args -join ' ') -ne 'config get modelRoles --json') { throw "Unexpected command: $args" }
    $fixture.Calls++
    $global:LASTEXITCODE = 0
    switch ($fixture.Mode) {
        'match' { '{"value":{"default":"local-inference/desired"}}' }
        'override' { '{"value":{"default":"existing-provider/existing-model"}}' }
        'missing' { '{"value":{}}' }
        'malformed' { 'not-json' }
        'exit' { $global:LASTEXITCODE = 9; '{}' }
        default { throw 'Unknown fixture' }
    }
}
foreach ($mode in @('match','override','missing','malformed','exit')) {
    $fixture.Mode = $mode
    $fixture.Calls = 0
    $messages = @(& $block 3>&1 6>&1)
    $output = ($messages | ForEach-Object { $_.ToString() }) -join "`n"
    if ($fixture.Calls -ne 1) { throw "$mode did not perform exactly one read-only request." }
    if ($mode -eq 'match') {
        if ($output -notmatch 'OMP effective default model here:' -or
            @($messages | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count -ne 0) {
            throw "Matching model not confirmed correctly: $output"
        }
    } else {
        if ($output -match 'OMP effective default model here:' -or $output -notmatch 'overrides were preserved') {
            throw "$mode falsely reported success or lost preservation warning: $output"
        }
        if (@($messages | Where-Object { $_ -is [System.Management.Automation.WarningRecord] }).Count -ne 1) {
            throw "$mode should produce exactly one warning."
        }
        if ($mode -eq 'override' -and $output -notmatch 'existing-provider/existing-model') {
            throw 'Override warning did not identify the effective model.'
        }
    }
}
$global:LASTEXITCODE = 0
Write-Host 'Effective-model readback: five safe cases passed.'
