# Safe source-fragment runtime regressions. No installers, networks or models are run.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
function Read-SourceAst([string]$Name) {
    $tokens = $null; $errors = $null
    $tree = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $Name), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$Name does not parse." }
    return $tree
}
$work = Join-Path ([IO.Path]::GetTempPath()) ('ai-regression-' + [guid]::NewGuid())
$originalPath = $env:Path
try {
    New-Item -ItemType Directory -Path $work | Out-Null
    $null = Read-SourceAst 'Install-Skills.ps1'
    $skillsSource = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Install-Skills.ps1'))
    $rulesBlock = [regex]::Match($skillsSource, '(?ms)^# BEGIN existing-rules initialization[^\r\n]*\r?\n(.*?)^# END existing-rules initialization')
    if (-not $rulesBlock.Success) { throw 'Missing bounded rules initialization block.' }
    $rules = Join-Path $work 'RULES.md'
    foreach ($expected in @('', 'existing rules')) {
        [IO.File]::WriteAllText($rules, $expected)
        $prior = 'UNASSIGNED-marker'
        Invoke-Expression $rulesBlock.Groups[1].Value
        if ($null -eq $prior -or $prior -cne $expected) {
            Write-Host ('Rules initialization source: ' + $rulesBlock.Groups[1].Value)
            Write-Host ('Expected JSON: ' + (ConvertTo-Json -InputObject $expected -Compress))
            Write-Host ('Actual JSON: ' + (ConvertTo-Json -InputObject $prior -Compress))
            throw 'Existing RULES.md content was not read unchanged.'
        }
    }
    Remove-Item -LiteralPath $rules
    $prior = 'UNASSIGNED-marker'
    Invoke-Expression $rulesBlock.Groups[1].Value
    if ($null -eq $prior -or $prior -cne '') { throw 'Missing RULES.md did not initialize an empty string.' }

    foreach ($name in @('Install-OMP.ps1', 'Install-Model.ps1')) {
        $tree = Read-SourceAst $name
        $assignment = $tree.Find({ param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$env:Path'
        }, $true)
        if (-not $assignment) { throw "Missing PATH refresh in $name." }
        $env:Path = 'C:\process-only-tool;C:\another-tool'
        Invoke-Expression $assignment.Extent.Text
        if (-not $env:Path.StartsWith('C:\process-only-tool;C:\another-tool')) { throw "$name discarded process PATH." }
    }

    $model = Read-SourceAst 'Install-Model.ps1'
    $guard = $model.Find({ param($node)
        $node -is [System.Management.Automation.Language.IfStatementAst] -and $node.Extent.Text -match "throw 'Strata installer failed\.'" -and $node.Extent.Text -notmatch 'Invoke-WebRequest'
    }, $true)
    if (-not $guard) { throw 'Missing Strata installer success guard.' }
    $installer = Join-Path $work 'fake-installer.ps1'
    Set-Content -LiteralPath $installer -Value '$global:LASTEXITCODE = 17; Write-Output "simulated successful fallback"'
    $invoke = [scriptblock]::Create('& $installer' + "`n" + $guard.Extent.Text)
    & $invoke | Out-Null
    Set-Content -LiteralPath $installer -Value 'throw "simulated installer failure"'
    try {
        & $invoke | Out-Null
        throw 'Failure was not propagated.'
    } catch {
        if ($_.Exception.Message -ne 'simulated installer failure') { throw }
    }
    Write-Host 'AI regression tests passed: empty rules, process PATH, and successful installer with stale native exit. No external software ran.'
} finally {
    $env:Path = $originalPath
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}
