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
$directDefinition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-DirectAppInstalled'}, $true)
$installerDefinition = $ast.Find({param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Run-Installer'}, $true)
if (-not $directDefinition -or -not $installerDefinition) { throw 'Direct installer detection missing.' }
& {
    Invoke-Expression $directDefinition.Extent.Text
    function Get-ItemProperty { param($Path,$ErrorAction) [pscustomobject]@{DisplayName='Paseo 0.99.0';DisplayVersion='0.99.0'} }
    if (-not (Test-DirectAppInstalled '^Paseo(?:$|\s)')) { throw 'Newer registered version must be preserved.' }
    if (Test-DirectAppInstalled '^SignalRGB(?:$|\s)') { throw 'Unrelated app falsely detected.' }
}
& {
    Invoke-Expression $installerDefinition.Extent.Text
    function Test-DirectAppInstalled { param($DisplayNamePattern) return $true }
    function Invoke-WebRequest { throw 'Existing application must not be downloaded again.' }
    function Start-Process { throw 'Existing application must not be installed again.' }
    Run-Installer 'https://example.invalid/unused.exe' 'unused.exe' -DisplayNamePattern '^Paseo(?:$|\s)'
}
& {
    Invoke-Expression $installerDefinition.Extent.Text
    function Test-DirectAppInstalled { param($DisplayNamePattern) return $false }
    function New-Item { param($ItemType,[switch]$Force,$Path) }
    function Invoke-WebRequest { param($Uri,$OutFile) }
    function Start-Process { param($FilePath,[switch]$Wait,[switch]$PassThru) return [pscustomobject]@{ExitCode=0} }
    $rejected = $false
    try { Run-Installer 'https://example.invalid/unused.exe' 'unused.exe' -DisplayNamePattern '^Paseo(?:$|\s)' }
    catch { if ($_.Exception.Message -match 'no matching installation') { $rejected=$true } else { throw } }
    if (-not $rejected) { throw 'Unregistered installer result must not count as complete.' }
}
Write-Host 'Mocked direct installer rerun and post-install checks passed. No installers ran.'
