# Safe runtime tests for SignalRGB detection. No installer, registry access or network.
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'Install-Apps.ps1')
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Install-Apps.ps1 does not parse.' }
foreach ($name in @('Test-DirectAppInstalled', 'Test-SignalRgbInstalled', 'Run-Installer')) {
    $definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }, $true)
    if (-not $definition) { throw "Required function missing: $name" }
    Invoke-Expression $definition.Extent.Text
}
$SignalRgbFixture = @{}
function Reset-Fixture {
    $SignalRgbFixture.Clear()
    $SignalRgbFixture.Paths = @()
    $SignalRgbFixture.Directories = @()
    $SignalRgbFixture.RegistryPresent = $false
    $SignalRgbFixture.CreateLauncher = $false
    $SignalRgbFixture.Downloads = 0
    $SignalRgbFixture.Starts = 0
}
function Get-ItemProperty {
    param([string]$Path, [string]$ErrorAction)
    if ($SignalRgbFixture.RegistryPresent) { return [pscustomobject]@{ DisplayName = 'SignalRGB 2.6' } }
    return @()
}
function Test-Path {
    param([string]$LiteralPath, [string]$PathType)
    if ($PathType -ne 'Leaf') { throw "Unexpected path type: $PathType" }
    return $LiteralPath -in $SignalRgbFixture.Paths
}
function Get-ChildItem {
    param([string]$LiteralPath, [switch]$Directory, [string]$Filter, [string]$ErrorAction)
    $allowed = @((Join-Path $env:LOCALAPPDATA 'VortexEngine'), (Join-Path $env:LOCALAPPDATA 'VortxEngine'))
    if ($LiteralPath -notin $allowed -or -not $Directory -or $Filter -ne 'app-*') {
        throw "Unsafe or unexpected directory enumeration: $LiteralPath"
    }
    foreach ($path in $SignalRgbFixture.Directories) {
        if ((Split-Path $path -Parent) -eq $LiteralPath) { [pscustomobject]@{ FullName = $path } }
    }
}
function New-Item {
    param([string]$ItemType, [switch]$Force, [string]$Path)
    # Do not create real directories for the production function's temporary path.
}
function Invoke-WebRequest {
    param([string]$Uri, [string]$OutFile)
    if ($Uri -ne 'https://release.signalrgb.com/Install_SignalRgb.exe') { throw "Unexpected URL: $Uri" }
    $SignalRgbFixture.Downloads++
}
function Start-Process {
    param([string]$FilePath, [switch]$Wait, [switch]$PassThru)
    $SignalRgbFixture.Starts++
    if ($SignalRgbFixture.CreateLauncher) {
        $version = Join-Path $env:LOCALAPPDATA 'VortexEngine\app-2.5.86'
        $SignalRgbFixture.Directories = @($version)
        $SignalRgbFixture.Paths = @((Join-Path $version 'SignalRgb.exe'))
    }
    return [pscustomobject]@{ ExitCode = 0 }
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (actual=$Actual expected=$Expected)" }
}
function Invoke-FixtureInstaller {
    Run-Installer 'https://release.signalrgb.com/Install_SignalRgb.exe' 'Install_SignalRgb.exe' -DisplayNamePattern '^SignalRGB(?:$|\s)' -SignalRgb
}

# Both spelling variants and root/versioned locations must skip reinstall.
$cases = 0
foreach ($engine in @('VortexEngine','VortxEngine')) {
    foreach ($relative in @('SignalRgbLauncher.exe','app-2.5.86\SignalRgb.exe','app-2.5.86\Signal-x64\SignalRgb.exe','app-2.5.86\SignalRgbLauncher.exe')) {
        Reset-Fixture
        $root = Join-Path $env:LOCALAPPDATA $engine
        $SignalRgbFixture.Paths = @((Join-Path $root $relative))
        $SignalRgbFixture.Directories = @((Join-Path $root 'app-2.5.86'))
        Invoke-FixtureInstaller
        Assert-Equal $SignalRgbFixture.Downloads 0 "Existing $engine/$relative must skip download"
        Assert-Equal $SignalRgbFixture.Starts 0 "Existing $engine/$relative must skip installer"
        $cases++
    }
}

Reset-Fixture
$SignalRgbFixture.RegistryPresent = $true
Invoke-FixtureInstaller
Assert-Equal $SignalRgbFixture.Downloads 0 'Existing registration must skip download'
Assert-Equal $SignalRgbFixture.Starts 0 'Existing registration must skip installer'
$cases++

Reset-Fixture
$SignalRgbFixture.CreateLauncher = $true
Invoke-FixtureInstaller
Assert-Equal $SignalRgbFixture.Downloads 1 'Fresh install must download once'
Assert-Equal $SignalRgbFixture.Starts 1 'Fresh install must run once'
Assert-Equal $SignalRgbFixture.Paths.Count 1 'Versioned executable should satisfy post-install check without registration'
$cases++

Reset-Fixture
$caught = $false
try { Invoke-FixtureInstaller } catch { $caught = $_.Exception.Message -like '*no matching installation*' }
Assert-Equal $caught $true 'Missing launcher and registry after success must fail clearly'
Assert-Equal $SignalRgbFixture.Starts 1 'Missing installation should still have attempted one installer'
$cases++
$global:LASTEXITCODE = 0
Write-Host "$cases SignalRGB detection scenarios passed. No installer, network or registry operation ran."
