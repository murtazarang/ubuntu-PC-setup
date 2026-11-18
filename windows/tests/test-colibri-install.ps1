# Actual download/dependency/UI smoke test. No model weights or GPU inference.
$ErrorActionPreference='Stop'
$base=Split-Path $PSScriptRoot -Parent
$work=Join-Path ([IO.Path]::GetTempPath()) ('colibri-test-'+[guid]::NewGuid())
$oldLocal=$env:LOCALAPPDATA
$oldHome=$env:USERPROFILE
$process=$null
New-Item -ItemType Directory -Path $work|Out-Null
try {
    $env:LOCALAPPDATA=$work
    $env:USERPROFILE=$work
    foreach($hardware in @('NvidiaSingle','NvidiaDual','Intel')){
        $env:LOCALAPPDATA=Join-Path $work $hardware
        New-Item -ItemType Directory -Path $env:LOCALAPPDATA -Force|Out-Null
        & (Join-Path $base 'Install-Colibri.ps1') -Hardware $hardware -NoShortcut -SkipModelDownload
        & (Join-Path $base 'Install-Colibri.ps1') -Hardware $hardware -NoShortcut -SkipModelDownload
    }
    $root=Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup'
    $config=Get-Content (Join-Path $root 'settings.json') -Raw|ConvertFrom-Json
    $python=Join-Path $config.release 'venv\Scripts\python.exe'
    $server=Join-Path $config.release 'app\ui\server.py'
    & $python (Join-Path $config.release 'app\coli') serve --help
    if($LASTEXITCODE){throw 'Real Colibri CLI help failed.'}
    & $python (Join-Path $config.release 'app\coli') import --help
    if($LASTEXITCODE){throw 'Real Colibri import help failed.'}
    & $python (Join-Path $config.release 'app\coli') web --help
    if($LASTEXITCODE){throw 'Real Colibri web help failed.'}
    $process=Start-Process -FilePath $python -ArgumentList @(('"'+$server+'"'),'--host','127.0.0.1','--port','18790','--backend','http://127.0.0.1:18000','--models-dir',('"'+(Join-Path $work 'models')+'"')) -PassThru
    $ready=$false
    for($i=0;$i -lt 30;$i++){
        try{$page=Invoke-WebRequest http://127.0.0.1:18790/ -UseBasicParsing -TimeoutSec 2;$ready=$page.StatusCode -eq 200;break}catch{Start-Sleep 1}
    }
    if(-not $ready){throw 'UI did not start without a model.'}
    $jobs=Invoke-RestMethod http://127.0.0.1:18790/models/jobs -TimeoutSec 10
    if(Test-Path (Join-Path $work 'models')){
        if(@(Get-ChildItem (Join-Path $work 'models') -Recurse -File).Count){throw 'Installer/UI unexpectedly created model files.'}
    }
    Write-Host 'Actual Colibri installation, rerun, CLI, UI and Models endpoint passed; no GPU or model inference tested.'
}finally{
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force}
    $env:LOCALAPPDATA=$oldLocal;$env:USERPROFILE=$oldHome
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
