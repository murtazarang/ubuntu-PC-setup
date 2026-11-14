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
    $skills = Read-SourceAst 'Install-Skills.ps1'
    $priorAssignment = $skills.Find({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -eq '$prior'
    }, $true)
    if (-not $priorAssignment) { throw 'Missing rules read statement.' }
    $rules = Join-Path $work 'RULES.md'
    [IO.File]::WriteAllText($rules, '')
    Invoke-Expression $priorAssignment.Extent.Text
    if ($null -eq $prior -or $prior.Contains('marker')) { throw 'Empty RULES.md was not normalized.' }
    [IO.File]::WriteAllText($rules, 'existing rules')
    Invoke-Expression $priorAssignment.Extent.Text
    if ($prior -ne 'existing rules') { throw 'Existing rules changed during read.' }

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
