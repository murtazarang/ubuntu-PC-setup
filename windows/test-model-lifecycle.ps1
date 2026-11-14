# Safe runtime tests: extract only the lifecycle function, mock every external action.
$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot 'Install-Model.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Install-Model.ps1 did not parse.' }
$definition = $ast.Find({ param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-XeStrataModel'
}, $true)
if ($null -eq $definition) { throw 'Lifecycle function not found.' }
Invoke-Expression $definition.Extent.Text
$script:running = @()
$script:prepared = 0
$script:started = 0
$script:prepareExit = 0
function Get-Process { param($Name, $ErrorAction) $script:running }
function fake-xestrata {
    $script:prepared++
    Write-Output 'Simulated native preparation progress'
    if ($args -notcontains '--no-start') { throw 'Preparation must not start the server.' }
    if ($args -notcontains 'Gyro-S') { throw 'Wrong model.' }
    $global:LASTEXITCODE = $script:prepareExit
}
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$PassThru)
    $script:started++
    if ($ArgumentList -contains '--setup' -or $ArgumentList -contains '--model') { throw 'Startup must not repeat preparation.' }
    if ($ArgumentList -notcontains '--yes') { throw 'Startup must select the newest saved config.' }
    [pscustomobject]@{ Path = $FilePath; Id = 123 }
}
$result = Start-XeStrataModel -Executable 'fake-xestrata'
if (@($result).Count -ne 1 -or $script:prepared -ne 1 -or $script:started -ne 1 -or $result.Id -ne 123) { throw 'Fresh preparation/start failed.' }
$script:running = @([pscustomobject]@{ Path = 'fake-xestrata'; Id = 456 })
$result = Start-XeStrataModel -Executable 'fake-xestrata'
if ($script:prepared -ne 1 -or $script:started -ne 1 -or $result.Id -ne 456) { throw 'Rerun created a duplicate.' }
$script:running = @()
$script:prepareExit = 7
try {
    $null = Start-XeStrataModel -Executable 'fake-xestrata'
    throw 'Expected preparation failure.'
} catch {
    if ($_.Exception.Message -notlike 'XeStrata preparation failed*') { throw }
}
if ($script:started -ne 1) { throw 'Started a server after failed preparation.' }
Write-Host 'Model preparation, duplicate prevention and failure propagation tests passed. No binaries or models were run.'
