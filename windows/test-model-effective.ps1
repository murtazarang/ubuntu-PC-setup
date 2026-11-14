# Safe: executes marked update/readback blocks with mocked OMP reads/writes.
# No endpoint, installer or real configuration writes.
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
        'array' { '[{"value":{"default":"local-inference/desired"}}]' }
        'exit' { $global:LASTEXITCODE = 9; '{}' }
        default { throw 'Unknown fixture' }
    }
}
foreach ($mode in @('match','override','missing','malformed','array','exit')) {
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
Write-Host 'Effective-model readback: six safe cases passed.'

# Verify global writes never copy project-only effective roles into global settings.
$globalMatch = [regex]::Match($text, '(?s)# BEGIN global-model update.*?\r?\n(.*?)# END global-model update')
if (-not $globalMatch.Success) { throw 'Global-model update block not found.' }
$globalBlock = [scriptblock]::Create($globalMatch.Groups[1].Value)
$globalFixture = @{ Json = ''; Exit = 0; Writes = 0; Written = $null }
function Invoke-MockGlobalOmp {
    $global:LASTEXITCODE = 0
    if (($args -join ' ') -eq 'config list --scope global --json') {
        $global:LASTEXITCODE = $globalFixture.Exit
        return $globalFixture.Json
    }
    if (($args -join ' ') -eq 'config get modelRoles --json') {
        return '{"value":{"default":"project/default","reviewer":"project/reviewer","projectOnly":"project/role"}}'
    }
    if ($args.Count -eq 4 -and ($args[0..2] -join ' ') -eq 'config set modelRoles') {
        $globalFixture.Writes++
        $globalFixture.Written = $args[3] | ConvertFrom-Json -AsHashtable
        return
    }
    throw "Unexpected global-write command: $args"
}
$omp = 'Invoke-MockGlobalOmp'
$cases = @(
    @{ Name='global-preserved'; Json='{"modelRoles":{"value":{"default":"old/global","reviewer":"global/reviewer"}}}'; Fail=$false },
    @{ Name='absent-valid'; Json='{}'; Fail=$false },
    @{ Name='null-invalid'; Json='{"modelRoles":{"value":null}}'; Fail=$true },
    @{ Name='list-invalid'; Json='{"modelRoles":{"value":[]}}'; Fail=$true },
    @{ Name='entry-invalid'; Json='{"modelRoles":null}'; Fail=$true },
    @{ Name='json-invalid'; Json='not-json'; Fail=$true },
    @{ Name='root-invalid'; Json='[]'; Fail=$true },
    @{ Name='single-array-invalid'; Json='[{"modelRoles":{"value":{"default":"old/global"}}}]'; Fail=$true },
    @{ Name='exit-invalid'; Json='{}'; Fail=$true }
)
foreach ($case in $cases) {
    $globalFixture.Json = $case.Json
    $globalFixture.Exit = if ($case.Name -eq 'exit-invalid') { 9 } else { 0 }
    $globalFixture.Writes = 0
    $globalFixture.Written = $null
    $failed = $false
    try { & $globalBlock } catch { $failed = $true }
    if ($failed -ne $case.Fail) { throw "Unexpected global-read result: $($case.Name)" }
    if ($case.Fail) {
        if ($globalFixture.Writes -ne 0) { throw "Malformed global settings were written: $($case.Name)" }
    } else {
        if ($globalFixture.Writes -ne 1 -or $globalFixture.Written.default -ne $selector) { throw 'Default was not updated exactly once.' }
        if ($case.Name -eq 'global-preserved' -and $globalFixture.Written.reviewer -ne 'global/reviewer') { throw 'Global reviewer role was changed.' }
        if ($case.Name -eq 'absent-valid' -and $globalFixture.Written.Count -ne 1) { throw 'Absent roles gained unexpected values.' }
        # Project roles only exist in effective readback, never in the scoped global response.
        if ($globalFixture.Written.Contains('projectOnly')) { throw 'Project-only role leaked globally.' }
    }
}
$global:LASTEXITCODE = 0
Write-Host 'Global-model preservation: nine safe cases passed.'

$globalFixture.Json = '{"modelRoles":{"value":{"default":"old/global","reviewer":"global/reviewer"}}}'
$globalFixture.Exit = 0
$globalFixture.Writes = 0
& $globalBlock
$after = @(& $block 3>&1 6>&1)
$afterText = ($after | ForEach-Object { $_.ToString() }) -join "`n"
if ($globalFixture.Written.reviewer -ne 'global/reviewer' -or
    $globalFixture.Written.Contains('projectOnly') -or
    $globalFixture.Writes -ne 1 -or
    $afterText -notmatch 'project/default' -or
    $afterText -match 'OMP effective default model here:') {
    throw 'Distinct global/project layers were not preserved and reported correctly.'
}
$global:LASTEXITCODE = 0
Write-Host 'Combined global/project preservation and effective override warning passed.'
