# Safe PS5.1/7 launcher tests: no network, installers, Python or USB access.
$ErrorActionPreference = 'Stop'
$code = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\install.ps1') -Raw
$root = Join-Path ([IO.Path]::GetTempPath()) ('ax-launcher-test-' + [guid]::NewGuid())
$script:Missing = $false
$script:FailSetup = $false
$oldPolicy = $env:PSExecutionPolicyPreference
# Restrict only this test process. Launcher must use child-process Bypass.
$env:PSExecutionPolicyPreference = 'Restricted'
function Get-Command {
    param($Name, $ErrorAction)
    if ($Name -ne 'uv.exe') { throw "Unexpected lookup: $Name" }
    [pscustomobject]@{ Source = 'MOCK-UV' }
}
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing)
    if ($Uri -ne 'https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip') { throw 'Wrong archive URL' }
    Set-Content -LiteralPath $OutFile -Value 'mock archive'
}
function Expand-Archive {
    param($LiteralPath, $DestinationPath)
    $files = Join-Path $DestinationPath 'ubuntu-PC-setup-main\windows\aida64_display'
    New-Item -ItemType Directory -Path $files -Force | Out-Null
    foreach ($name in @('panel.py','portrait.yaml','LICENSE','autostart.ps1')) { Set-Content -LiteralPath (Join-Path $files $name) -Value 'mock asset' }
    if ($script:Missing) { return }
    $setup = @'
param($InstallDir,$Rotation)
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'panel.py'))) { throw 'PSScriptRoot was lost' }
Set-Content -LiteralPath (Join-Path $InstallDir 'setup-called') -Value $PSScriptRoot
'@
    # Put the failure directly into the generated script, independent of scope.
    if ($script:FailSetup) { $setup = "param(`$InstallDir,`$Rotation)`nthrow 'Mock setup failure'" }
    Set-Content -LiteralPath (Join-Path $files 'Setup.ps1') -Value $setup
    $runner = 'param($InstallDir,$Rotation) Set-Content -LiteralPath (Join-Path $InstallDir "run-called") -Value $Rotation'
    Set-Content -LiteralPath (Join-Path $files 'Run.ps1') -Value $runner
}
function Assert([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    $install = Join-Path $root "path with spaces and apostrophe's"
    New-Item -ItemType Directory -Path $install -Force | Out-Null
    Assert ((Get-ExecutionPolicy) -eq 'Restricted') 'Restricted policy is not effective; test invalid.'
    $probe = Join-Path $root 'restricted-probe.ps1'
    Set-Content -LiteralPath $probe -Value "throw 'Restricted policy failed to block this file'"
    $blocked = $false
    try { & $probe } catch [System.Management.Automation.PSSecurityException] { $blocked = $true }
    Assert $blocked 'Restricted policy did not block direct script execution; test invalid.'
    Set-Content -LiteralPath (Join-Path $install 'portrait.yaml') -Value 'MY CUSTOM THEME'
    $Rotation = 'invalid caller value'
    $InstallDir = 'do not modify caller'
    & ([scriptblock]::Create($code)) -InstallDir $install -SetupOnly
    Assert ($Rotation -eq 'invalid caller value' -and $InstallDir -eq 'do not modify caller') 'Caller variables changed'
    Assert (Test-Path -LiteralPath (Join-Path $install 'Run.ps1')) 'Durable runner missing'
    Assert (-not (Test-Path -LiteralPath (Join-Path $install 'run-called'))) 'SetupOnly started hardware runner'
    Assert ((Get-Content -LiteralPath (Join-Path $install 'portrait.yaml') -Raw).Trim() -eq 'MY CUSTOM THEME') 'Existing theme overwritten'
    & ([scriptblock]::Create($code)) -InstallDir $install -Rotation 90
    Assert (-not (Test-Path -LiteralPath (Join-Path $install 'run-called'))) 'Default installation started a second foreground display'
    # Real iex call with colliding caller variables uses its default location.
    $oldLocal = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = Join-Path $root 'iex profile'
    try { Invoke-Expression $code } finally { $env:LOCALAPPDATA = $oldLocal }
    Assert ($Rotation -eq 'invalid caller value') 'iex leaked parameter attributes or values'
    foreach ($kind in @('Missing','FailSetup')) {
        $script:Missing = $kind -eq 'Missing'; $script:FailSetup = $kind -eq 'FailSetup'
        $target = Join-Path $root $kind
        $failed = $false
        try { & ([scriptblock]::Create($code)) -InstallDir $target } catch {
            $failed = $_.Exception.Message -like '*missing AX206 file*' -or $_.Exception.Message -like '*Setup.ps1 failed with exit code*' -or $_.Exception.Message -like '*Run.ps1 failed with exit code 17*'
        }
        Assert $failed "Failure was not propagated: $kind"
        Assert (-not (Test-Path -LiteralPath (Join-Path $target 'run-called'))) 'Runner launched after failure'
        Assert (Test-Path -LiteralPath (Join-Path $target 'setup-runs')) 'Failure recovery files missing'
    }
    Assert ($env:PSExecutionPolicyPreference -eq 'Restricted') 'Launcher changed caller execution policy'
    Write-Host 'PASS: Restricted parent policy, real child host and exit propagation, launcher scope, real iex, path quoting, setup-only, no duplicate foreground start, rerun preservation and failure propagation.'
} finally {
    $env:PSExecutionPolicyPreference = $oldPolicy
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    $global:LASTEXITCODE = 0
}

