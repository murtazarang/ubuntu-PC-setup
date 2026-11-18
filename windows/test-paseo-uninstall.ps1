# Safe fixtures only: no installed application or real registry entry is changed.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Remove-LegacyAI.ps1')
$reported='"C:\Users\main\AppData\Local\Programs\Paseo\Uninstall Paseo.exe" /currentuser'
$c=Resolve-PaseoUninstallCommand $reported
if($c.Executable -cne 'C:\Users\main\AppData\Local\Programs\Paseo\Uninstall Paseo.exe' -or $c.Scope -cne '/currentuser'){throw 'Reported registry command parsed incorrectly.'}
foreach($raw in @('"C:\Paseo\Uninstall Paseo.exe" /S','"C:\Paseo\Uninstall Paseo.exe" /currentuser /S','"C:\Paseo\Uninstall Paseo.exe" & calc.exe','"C:\Paseo\Uninstall Paseo.exe" /unknown',"`"C:\Paseo\uninstall.exe`"`ncalc.exe")){
    $rejected=$false
    try{$null=Resolve-PaseoUninstallCommand $raw}catch{$rejected=$true}
    if(-not $rejected){throw "Unsafe/unknown argument accepted: $raw"}
}
foreach($scope in @('/currentuser','/allusers','')){
    $raw='"C:\Users\main\AppData\Local\Programs\Paseo\Uninstall Paseo.exe"'+$(if($scope){' '+$scope}else{''})
    $c=Resolve-PaseoUninstallCommand $raw
    function Test-Path {param($LiteralPath,$PathType) $LiteralPath -eq 'C:\Users\main\AppData\Local\Programs\Paseo\Uninstall Paseo.exe' -and $PathType -eq 'Leaf'}
    $script:seen=$null
    function Start-Process {param($FilePath,$ArgumentList,[switch]$Wait,[switch]$PassThru)
        $script:seen=@{FilePath=$FilePath;Arguments=@($ArgumentList);Wait=$Wait;PassThru=$PassThru}
        [pscustomobject]@{ExitCode=0}
    }
    $p=Invoke-PaseoUninstaller $c
    if($script:seen.FilePath -cne $c.Executable -or -not $script:seen.Wait -or -not $script:seen.PassThru){throw 'Wrong process invocation.'}
    if($scope -and ($script:seen.Arguments.Count -ne 1 -or $script:seen.Arguments[0] -cne $scope)){throw 'Registered scope was not forwarded exactly.'}
    if(-not $scope -and @($script:seen.Arguments|Where-Object {$_}).Count){throw 'Unexpected argument added.'}
    Remove-Item Function:\Start-Process,Function:\Test-Path
}
# Execute a purpose-built, harmless Windows EXE through the production helper.
# This exercises real CreateProcess argument handling; it is not a Paseo uninstall.
if($env:OS -eq 'Windows_NT'){
    $work=Join-Path ([IO.Path]::GetTempPath()) ('paseo uninstall fixture '+[guid]::NewGuid())
    $oldLog=$env:PASEO_FIXTURE_LOG
    New-Item -ItemType Directory -Path $work|Out-Null
    try{
        $exe=Join-Path $work 'Uninstall Paseo.exe';$source=Join-Path $work 'fixture.cs'
        $env:PASEO_FIXTURE_LOG=Join-Path $work 'args.txt'
        @'
using System; using System.IO;
class Fixture { static int Main(string[] args) { File.WriteAllLines(Environment.GetEnvironmentVariable("PASEO_FIXTURE_LOG"), args); return 0; } }
'@ | Set-Content -LiteralPath $source -Encoding utf8
        $csc=Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        if(-not(Test-Path -LiteralPath $csc)){throw 'Windows compiler fixture prerequisite missing; native argument test must not silently skip.'}
        & $csc /nologo /target:exe ("/out:$exe") $source
        if($LASTEXITCODE){throw 'Could not compile harmless uninstall fixture.'}
        foreach($scope in @('/currentuser','/allusers')){
            $command=Resolve-PaseoUninstallCommand ('"'+$exe+'" '+$scope)
            $process=Invoke-PaseoUninstaller $command
            if($process.ExitCode -ne 0 -or (Get-Content -LiteralPath $env:PASEO_FIXTURE_LOG -Raw).Trim() -cne $scope){throw 'Real Windows EXE did not receive the registered scope exactly.'}
        }
        Write-Host 'Real Windows process fixture passed; no Paseo application or registry was touched.'
    }finally{$env:PASEO_FIXTURE_LOG=$oldLog;Remove-Item -LiteralPath $work -Recurse -Force}
}
Write-Host 'Paseo uninstall command parsing and exact scope forwarding fixtures passed.'
