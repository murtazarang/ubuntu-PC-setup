# Execute only the actual installer wrapper with a mock WinGet; no installation.
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\Install-Apps.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Parse errors: $errors" }
$fn = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Install-WingetApp' }, $true)
if (-not $fn) { throw 'Installer wrapper not found' }
. ([scriptblock]::Create($fn.Extent.Text))
function winget.exe {
    $global:captured = @($args)
    $global:LASTEXITCODE = $global:mockExit
}
$global:mockExit = 0
Install-WingetApp 'Mozilla.Firefox'
if (($global:captured -join ' ') -ne 'install --exact --id Mozilla.Firefox --source winget --accept-source-agreements --accept-package-agreements --disable-interactivity --no-upgrade --installer-type exe') { throw 'Firefox arguments incorrect' }
Install-WingetApp 'Valve.Steam'
if ($global:captured -contains '--installer-type') { throw 'Installer type leaked into another app' }
if ($global:captured -notcontains '--no-upgrade') { throw 'Rerun preservation flag missing' }
# WinGet already-installed statuses must not fail or trigger another command.
foreach ($status in @(0x8A150061L,0x8A15010DL)) {
    $global:mockExit = $status
    Install-WingetApp 'Mozilla.Firefox'
}
$global:mockExit = 1
$failed = $false
try { Install-WingetApp 'Mozilla.Firefox' } catch { $failed = $true }
if (-not $failed) { throw 'Failed installer must stop setup' }
Write-Host 'Firefox installer-type mocked checks passed.'
