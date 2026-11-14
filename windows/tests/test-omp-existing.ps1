# Extract only the production resolver: never invoke the installer or app.
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-OMP.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($target, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Install-OMP parse failed' }
$definition = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-ExistingOmp'}, $true)
if (-not $definition) { throw 'Missing production resolver' }
. ([scriptblock]::Create($definition.Extent.Text))
$OmpFixture = @{ Active = $null; Binary = $null; File = $false }
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    if ($Name -eq 'omp') { return $OmpFixture.Active }
    if ($Name -eq 'omp.exe') { return $OmpFixture.Binary }
    throw "Unexpected lookup $Name"
}
function Test-Path { param($LiteralPath, $PathType) return $OmpFixture.File }
$before = $env:Path
$installBefore = $env:PI_INSTALL_DIR
try {
    $OmpFixture.Active = [pscustomobject]@{ Source = 'C:\custom\omp.exe' }
    if ((Find-ExistingOmp).Source -ne 'C:\custom\omp.exe') { throw 'Active binary not preserved' }
    $OmpFixture.Active = [pscustomobject]@{ Source = 'C:\custom\omp.cmd' }
    try { Find-ExistingOmp; throw 'Expected source-install rejection' }
    catch { if ($_.Exception.Message -notlike 'Existing OMP installation found*') { throw } }
    $OmpFixture.Active = $null
    $OmpFixture.Binary = [pscustomobject]@{ Source = 'C:\binary\omp.exe' }
    if ((Find-ExistingOmp).Source -ne 'C:\binary\omp.exe') { throw 'Binary lookup not preserved' }
    $OmpFixture.Binary = $null
    $OmpFixture.File = $true
    $env:PI_INSTALL_DIR = 'C:\custom-override'
    if ((Find-ExistingOmp).Source -ne 'C:\custom-override\omp.exe') { throw 'Install override not detected' }
    $OmpFixture.File = $false
    if ($null -ne (Find-ExistingOmp)) { throw 'Absent binary incorrectly detected' }
    Write-Host 'Five OMP discovery cases passed; no installer or application was run.'
} finally { $env:Path = $before; $env:PI_INSTALL_DIR = $installBefore }
$global:LASTEXITCODE = 0
