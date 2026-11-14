# Non-destructive tests: extract detection functions without running app installs.
$ErrorActionPreference = 'Stop'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'Install-Apps.ps1'), [ref]$tokens, [ref]$errors)
$definition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-SpotifyInstalled'}, $true)
if (-not $definition) { throw 'Spotify detection function missing.' }
& {
    Invoke-Expression $definition.Extent.Text
    function Get-ItemProperty { param($Path,$ErrorAction) [pscustomobject]@{DisplayName='Spotify';DisplayVersion='existing'} }
    function Test-Path { throw 'Registry detection should short-circuit before filesystem/package checks.' }
    if (-not (Test-SpotifyInstalled)) { throw 'Existing Spotify registry installation not detected.' }
}
& {
    Invoke-Expression $definition.Extent.Text
    function Get-ItemProperty { param($Path,$ErrorAction) [pscustomobject]@{DisplayName='Other App'} }
    function Test-Path { param($LiteralPath) return $true }
    if (-not (Test-SpotifyInstalled)) { throw 'Existing per-user Spotify executable not detected.' }
}
Write-Host 'Mocked Spotify Win32 detection passed. No installer or Store operation ran.'
