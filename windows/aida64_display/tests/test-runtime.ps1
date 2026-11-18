# Real isolated Windows runtime installation. No service/task/driver/USB actions.
# Exercises the exact production helper, not a copied or mocked uv command list.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Service.ps1') -FunctionsOnly
function New-Service {throw 'Runtime test must not create services'}
function Stop-Service {throw 'Runtime test must not stop services'}
function Start-Service {throw 'Runtime test must not start services'}
function Register-ScheduledTask {throw 'Runtime test must not register tasks'}
function Invoke-StartupMigration {throw 'Runtime test must not migrate startup'}
$uvPath=(Get-Command uv.exe -ErrorAction Stop).Source
$assets=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$work=Join-Path ([IO.Path]::GetTempPath()) ('AX206 real staging '+[guid]::NewGuid())
$beforePython=$env:UV_PYTHON_INSTALL_DIR
$beforeCache=$env:UV_CACHE_DIR
function Assert($Value,$Message) {if(-not $Value){throw $Message}}
function Assert-EnvironmentRestored {
    Assert ($env:UV_PYTHON_INSTALL_DIR -eq $beforePython) 'Python install environment leaked'
    Assert ($env:UV_CACHE_DIR -eq $beforeCache) 'uv cache environment leaked'
}
New-Item -ItemType Directory $work | Out-Null
try {
    $commit='11280756789f1d61b80b49383b255acde62a9c60'
    $zip=Join-Path $work 'source.zip'
    Invoke-WebRequest "https://github.com/mechcow/win-ax206-display/archive/$commit.zip" -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $work
    $unpacked=Join-Path $work "win-ax206-display-$commit"
    foreach ($caseName in @('fresh install','recovery after failed stage')) {
        $release=Join-Path $work $caseName
        New-Item -ItemType Directory $release | Out-Null
        $source=Join-Path $release 'source'
        Copy-Item -LiteralPath $unpacked -Destination $source -Recurse
        if ($caseName -eq 'recovery after failed stage') {
            $badSource=Join-Path $release 'invalid project'
            New-Item -ItemType Directory $badSource | Out-Null
            $failed=$false
            try {Initialize-ServiceRuntime -Release $release -Source $badSource -UvExe $uvPath} catch {$failed=$true;Write-Host "Expected failed stage: $_"}
            Assert $failed 'Invalid project did not fail dependency staging'
            Assert-EnvironmentRestored
            Assert (Test-Path (Join-Path $release '.venv\Scripts\python.exe')) 'Failure did not reach actual venv creation'
        }
        Initialize-ServiceRuntime -Release $release -Source $source -UvExe $uvPath
        Assert-EnvironmentRestored
        $python=Join-Path $release '.venv\Scripts\python.exe'
        Invoke-CheckedNative $python @('-E','-s','-c','import servicemanager,win32service,win32serviceutil,ax206panel')
        Write-Host 'Actual runtime imports passed'
        Assert (Test-Path (Join-Path $source 'lib\LibreHardwareMonitorLib.dll')) 'LHM extraction failed'
        foreach ($name in @('panel.py','lifecycle.py','safe_theme.py','portrait.yaml')) {Copy-Item (Join-Path $assets $name) $release}
        Invoke-CheckedNative $python @('-E','-s',(Join-Path $release 'safe_theme.py'),(Join-Path $release 'portrait.yaml'))
        Invoke-CheckedNative $python @('-E','-s',(Join-Path $release 'panel.py'),'--preview',(Join-Path $release 'preview.png'))
        Assert (Test-Path (Join-Path $release 'preview.png')) 'Actual preview failed'
        $marker=Join-Path $release '.venv\preserve-on-rerun.txt'
        Set-Content $marker 'preserve this file'
        Initialize-ServiceRuntime -Release $release -Source $source -UvExe $uvPath
        Assert-EnvironmentRestored
        Assert ((Get-Content $marker -Raw).Trim() -eq 'preserve this file') 'Rerun cleared the environment'
        Write-Host "PASS: actual $caseName and rerun; no service or hardware access"
    }
} finally {
    $env:UV_PYTHON_INSTALL_DIR=$beforePython
    $env:UV_CACHE_DIR=$beforeCache
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
