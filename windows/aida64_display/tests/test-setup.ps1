# Safe Windows PowerShell 5.1 / PowerShell 7 control-flow tests.
# Only two native process call sites are replaced with in-process test doubles.
# No installer, Python, uv, downloads or hardware operations are executed.
$ErrorActionPreference = 'Stop'
$setup = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\Setup.ps1') -Raw
if ([regex]::Matches($setup, '& \$uv\.Source').Count -ne 2 -or
    [regex]::Matches($setup, '& \$python ').Count -ne 1) {
    throw 'Setup native invocation interface changed; review mocks before running.'
}
$isolated = $setup.Replace('& $uv.Source', 'Invoke-FakeUv').Replace('& $python ', 'Invoke-FakePython ')
# Preserve the original script's asset root when executing the detached block.
$script:Assets = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$isolated = $isolated.Replace('$PSScriptRoot', '$script:Assets')
$script:Code = [scriptblock]::Create($isolated)
$script:Events = [System.Collections.Generic.List[string]]::new()
$script:UvFails = $false
$script:UvMissing = $false
function Get-Command {
    param([string]$Name, [object]$ErrorAction)
    if ($Name -ne 'uv.exe') { throw "Unexpected command lookup: $Name" }
    if ($script:UvMissing) { return $null }
    [pscustomobject]@{ Source = 'FAKE-UV-NOT-EXECUTABLE' }
}
function Invoke-FakeUv {
    $script:Events.Add('uv:' + ($args -join '|'))
    $global:LASTEXITCODE = if ($script:UvFails) { 23 } else { 0 }
}
function Invoke-FakePython {
    if ($args.Count -ne 1 -or $args[0] -notlike '*tools\fetch_lhm.py') {
        throw "Unexpected Python invocation: $args"
    }
    $script:Events.Add('fetch')
    Set-Content -LiteralPath $script:Dll -Value 'MOCK DLL, NOT EXECUTABLE'
    $global:LASTEXITCODE = 0
}
function Invoke-WebRequest { throw 'Unexpected network operation during rerun test.' }
function Expand-Archive { throw 'Unexpected archive extraction during rerun test.' }
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('ax206-test-' + [guid]::NewGuid())
$install = Join-Path $root 'custom install path with spaces'
$source = Join-Path $install 'win-ax206-display-11280756789f1d61b80b49383b255acde62a9c60'
$script:Dll = Join-Path $source 'lib\LibreHardwareMonitorLib.dll'
try {
    New-Item -ItemType Directory -Path (Join-Path $source 'lib'), (Join-Path $install '.venv\Scripts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $install '.venv\Scripts\python.exe') -Value 'MOCK, NOT EXECUTABLE'
    Set-Content -LiteralPath $script:Dll -Value 'MOCK DLL, NOT EXECUTABLE'
    Set-Content -LiteralPath (Join-Path $source 'lib\setup-complete.txt') -Value 'complete'
    Set-Content -LiteralPath (Join-Path $install 'portrait.yaml') -Value 'CUSTOM THEME MUST SURVIVE'
    & $script:Code -InstallDir $install
    Assert-True ($script:Events.Count -eq 1 -and $script:Events[0].StartsWith('uv:pip|install|')) 'Rerun should only ensure editable package installation.'
    Assert-True ($script:Events[0].Contains($install)) 'Custom install path was not passed as one preserved argument.'
    Assert-True ((Get-Content -LiteralPath (Join-Path $install 'portrait.yaml') -Raw).Trim() -eq 'CUSTOM THEME MUST SURVIVE') 'Custom theme was overwritten.'
    Assert-True (Test-Path -LiteralPath (Join-Path $install 'panel.py')) 'Runner not copied.'

    $script:Events.Clear()
    Remove-Item -LiteralPath $script:Dll
    & $script:Code -InstallDir $install
    Assert-True ($script:Events.Contains('fetch')) 'Missing DLL must trigger fetch even with marker present.'

    $script:Events.Clear(); $script:UvFails = $true
    Remove-Item -LiteralPath $script:Dll
    $failed = $false
    try { & $script:Code -InstallDir $install } catch {
        $failed = $_.Exception.Message -like '*dependencies failed*'
    }
    Assert-True $failed 'uv installation failure did not stop setup.'
    Assert-True (-not $script:Events.Contains('fetch')) 'Library fetching continued after uv failed.'

    $script:UvFails = $false; $script:UvMissing = $true
    $absent = Join-Path $root 'must not create'
    $failed = $false
    try { & $script:Code -InstallDir $absent } catch {
        $failed = $_.Exception.Message -like '*uv is required*'
    }
    Assert-True $failed 'Missing uv did not produce expected failure.'
    Assert-True (-not (Test-Path -LiteralPath $absent)) 'Setup mutated install path before checking uv.'
    Write-Host 'PASS: rerun, preserved theme, path with spaces, missing DLL refetch, uv failure and missing uv.'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
