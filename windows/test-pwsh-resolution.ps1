# Safe launcher regression tests. No WinGet, PowerShell binary or installer runs.
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'run.ps1')
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Launcher does not parse.' }
$definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Find-PowerShell7' }, $true)
if (-not $definition) { throw 'Find-PowerShell7 definition missing.' }
Invoke-Expression $definition.Extent.Text
$start = $source.IndexOf('$candidate = Find-PowerShell7', $definition.Extent.EndOffset)
$end = $source.IndexOf('$dir =', $start)
if ($start -lt 0 -or $end -le $start) { throw 'Safe resolution/install boundary missing; update test.' }
$resolveAndInstall = $source.Substring($start, $end - $start)
$PowerShellResolutionFixture = @{}
function Reset-Fixture {
    $PowerShellResolutionFixture.Clear()
    $PowerShellResolutionFixture.CommandPath = $null
    $PowerShellResolutionFixture.Paths = @()
    $PowerShellResolutionFixture.Packages = @()
    $PowerShellResolutionFixture.AppxAvailable = $true
    $PowerShellResolutionFixture.InstallCalls = 0
    $PowerShellResolutionFixture.InstallCode = 0
    $PowerShellResolutionFixture.InstallMsix = $false
    $global:LASTEXITCODE = 0
}
function Get-Command {
    param([string]$Name, [string]$CommandType, [string]$ErrorAction)
    switch ($Name) {
        'pwsh.exe' { if ($PowerShellResolutionFixture.CommandPath) { [pscustomobject]@{ Source = $PowerShellResolutionFixture.CommandPath } } }
        'Get-AppxPackage' { if ($PowerShellResolutionFixture.AppxAvailable) { [pscustomobject]@{ Name = 'Get-AppxPackage' } } }
        default { throw "Unexpected command lookup: $Name" }
    }
}
function Test-PowerShell7Candidate {
    param([string]$Candidate)
    return $Candidate -in $PowerShellResolutionFixture.Paths
}
function Test-Path {
    param([string]$LiteralPath, [string]$PathType)
    return $LiteralPath -in $PowerShellResolutionFixture.Paths
}
function Get-AppxPackage {
    param([string]$Name, [string]$ErrorAction)
    if ($Name -ne 'Microsoft.PowerShell') { throw "Unexpected package lookup: $Name" }
    return $PowerShellResolutionFixture.Packages
}
function winget.exe {
    $PowerShellResolutionFixture.InstallCalls++
    if ($args -notcontains 'Microsoft.PowerShell') { throw 'Unexpected WinGet package.' }
    if ($PowerShellResolutionFixture.InstallMsix) {
        $PowerShellResolutionFixture.Packages = @([pscustomobject]@{ Version = [version]'7.6.6.0'; InstallLocation = 'C:\Fixture\WindowsApps\Microsoft.PowerShell' })
        $PowerShellResolutionFixture.Paths = @('C:\Fixture\WindowsApps\Microsoft.PowerShell\pwsh.exe')
    }
    $global:LASTEXITCODE = $PowerShellResolutionFixture.InstallCode
}
function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) { throw "$Message (actual='$Actual'; expected='$Expected')" }
}

# Existing alias is preserved and never triggers another installation.
Reset-Fixture
$PowerShellResolutionFixture.CommandPath = 'C:\Fixture\WindowsApps\pwsh.exe'
$PowerShellResolutionFixture.Paths = @($PowerShellResolutionFixture.CommandPath)
Invoke-Expression $resolveAndInstall
Assert-Equal $candidate $PowerShellResolutionFixture.CommandPath 'Existing alias not selected'
Assert-Equal $PowerShellResolutionFixture.InstallCalls 0 'Alias caused redundant installation'

# Existing MSI is found even when the current process PATH is stale.
Reset-Fixture
$msiPath = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
$PowerShellResolutionFixture.Paths = @($msiPath)
Invoke-Expression $resolveAndInstall
Assert-Equal $candidate $msiPath 'MSI fallback failed'
Assert-Equal $PowerShellResolutionFixture.InstallCalls 0 'Existing MSI caused installation'

# Registered MSIX does not require the alias to have appeared in this session.
Reset-Fixture
$PowerShellResolutionFixture.Packages = @([pscustomobject]@{ Version = [version]'7.6.6.0'; InstallLocation = 'C:\Fixture\WindowsApps\Microsoft.PowerShell' })
$msixPath = 'C:\Fixture\WindowsApps\Microsoft.PowerShell\pwsh.exe'
$PowerShellResolutionFixture.Paths = @($msixPath)
Invoke-Expression $resolveAndInstall
Assert-Equal $candidate $msixPath 'Existing MSIX fallback failed'
Assert-Equal $PowerShellResolutionFixture.InstallCalls 0 'Existing MSIX caused installation'

# Reproduce reported case: successful install creates MSIX, not MSI or PATH entry.
Reset-Fixture
$PowerShellResolutionFixture.InstallMsix = $true
Invoke-Expression $resolveAndInstall
Assert-Equal $candidate $msixPath 'Fresh MSIX not re-resolved after WinGet success'
Assert-Equal $PowerShellResolutionFixture.InstallCalls 1 'Expected one installation'

Reset-Fixture
$caught = $false
try { Invoke-Expression $resolveAndInstall } catch { $caught = $_.Exception.Message -like '*not located after installation*' }
Assert-Equal $caught $true 'Successful WinGet with no executable must fail clearly'

Reset-Fixture
$PowerShellResolutionFixture.InstallCode = 1
$caught = $false
try { Invoke-Expression $resolveAndInstall } catch { $caught = $_.Exception.Message -like '*installation failed*' }
Assert-Equal $caught $true 'Failed WinGet must not continue'
$global:LASTEXITCODE = 0
Write-Host 'Six PowerShell resolution scenarios passed; no native command or installation ran.'
