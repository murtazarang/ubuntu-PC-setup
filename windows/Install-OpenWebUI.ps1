# Native Windows only. No OMP, Docker, WSL, cloud account or network exposure.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$colibri=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup\settings.json') -Raw|ConvertFrom-Json
if($colibri.hardware -eq 'Intel'){throw 'Intel Open WebUI GPU configuration is pending an explicitly supported choice. No CPU fallback was installed.'}
# PyTorch official Windows/Linux 2.9.1 CUDA12.8 wheels; source-matched WebUI CUDA path.
$TorchBackend='cu128'
$uv=(Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
$root=Join-Path $env:LOCALAPPDATA 'OpenWebUI-PC-Setup'
New-Item -ItemType Directory -Path $root -Force|Out-Null
$python=Join-Path $root 'venv\Scripts\python.exe'
& $uv venv --no-project --allow-existing --python 3.11 (Join-Path $root 'venv')
if($LASTEXITCODE -ne 0){throw 'Open WebUI Python environment creation failed.'}
# CUDA supporting models are authorized. Exact backend must match tested driver compatibility.
$installHelp=(& $uv pip install --help | Out-String)
if($LASTEXITCODE -ne 0 -or $installHelp -notmatch '--torch-backend'){throw 'Installed uv does not support --torch-backend. Update uv using its installation method, then rerun.'}
& $uv pip install --torch-backend $TorchBackend --python $python 'open-webui==0.13.4' 'torch==2.9.1' 'psutil==7.2.2'
if($LASTEXITCODE -ne 0){throw 'Open WebUI dependencies failed. Rerun to retry; existing data is retained.'}
& $python -c "import torch; assert torch.cuda.is_available(), 'CUDA unavailable; no CPU fallback. Check NVIDIA driver/CUDA wheel compatibility.'; print('CUDA supporting-model device:', torch.cuda.get_device_name(0))"
if($LASTEXITCODE -ne 0){throw 'Open WebUI CUDA verification failed. No CPU fallback was configured.'}
$colibri=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup\settings.json') -Raw|ConvertFrom-Json
# mcpo requires its own compatible SDK/FastAPI, separate from WebUI and OpenZIM.
$bridgePython=Join-Path $root 'mcpo-venv\Scripts\python.exe'
& $uv venv --no-project --allow-existing --python 3.11 (Join-Path $root 'mcpo-venv')
if($LASTEXITCODE -ne 0){throw 'mcpo environment creation failed.'}
& $uv pip install --python $bridgePython 'mcpo==0.0.20' 'mcp==1.30.0' 'fastapi==0.115.12'
if($LASTEXITCODE -ne 0){throw 'mcpo compatible dependencies failed.'}
$reference=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'OpenZIM\reference.json') -Raw|ConvertFrom-Json
$modelKey=if($colibri.hardware -eq 'NvidiaDual'){'flash-next-iq2-xs'}else{'dense27b'}
$keyPath=Join-Path $root 'wikipedia-api-key'
if(-not(Test-Path -LiteralPath $keyPath)){
    & $python -c "import pathlib,secrets,sys; pathlib.Path(sys.argv[1]).write_text(secrets.token_urlsafe(32),encoding='utf-8')" $keyPath
    if($LASTEXITCODE -ne 0){throw 'Local Wikipedia bridge key creation failed.'}
}
$wikiKey=(Get-Content -LiteralPath $keyPath -Raw).Trim()
$configPath=Join-Path $root 'desktop.json'
if(-not(Test-Path -LiteralPath $configPath)){
    @{
        hardware=$colibri.hardware
        coli_python=(Join-Path $colibri.release 'venv\Scripts\python.exe')
        coli=(Join-Path $colibri.release 'app\coli')
        text_model=(Join-Path $colibri.models "$modelKey\model")
        image_model=(Join-Path $colibri.models 'qwen-image-2.1\model')
        webui_command=@((Join-Path $root 'venv\Scripts\open-webui.exe'),'serve','--host','127.0.0.1','--port','8080')
        mcpo_command=@((Join-Path $root 'mcpo-venv\Scripts\mcpo.exe'),'--host','127.0.0.1','--port','8002','--api-key',$wikiKey,'--',$reference.bridge,$reference.archive_directory)
        webui_environment=@{WEBUI_AUTH='true';USE_CUDA_DOCKER='true';USE_SLIM_DOCKER='false';OPENAI_API_BASE_URL='http://127.0.0.1:8000/v1';OPENAI_API_KEY='local-colibri';ENABLE_OLLAMA_API='false';ENABLE_WEB_SEARCH='true';WEB_SEARCH_ENGINE='duckduckgo'}
    }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $configPath -Encoding utf8
}else{Write-Host "Preserving existing runtime settings: $configPath"}
foreach($icon in @('colibri-serve.ico','colibri-serve-image.ico')){
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) ('assets\colibri\'+$icon)) -Destination (Join-Path $root $icon) -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'openwebui_desktop.py') -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Finish-OpenWebUI.ps1') -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Remove-VerifiedOMP.ps1') -Destination $root -Force
$repo=Split-Path $PSScriptRoot -Parent
Copy-Item -LiteralPath (Join-Path $repo 'openwebui_skills.py') -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $repo 'openwebui_connections.py') -Destination $root -Force
& $python (Join-Path $root 'openwebui_skills.py') prepare --root (Join-Path $root 'skill-repos')
if($LASTEXITCODE -ne 0){throw 'Full skill repository preparation failed; old skills are untouched.'}
$desktop=[Environment]::GetFolderPath('Desktop')
$shell=New-Object -ComObject WScript.Shell
foreach($item in @(@{name='Colibri Serve';action='text';icon='colibri-serve.ico'},@{name='Colibri Serve Image';action='image';icon='colibri-serve-image.ico'},@{name='Stop Colibri Model';action='stop';icon='colibri-serve.ico'},@{name='Open WebUI';action='ui';icon='colibri-serve.ico'})){
    $file=Join-Path $desktop ($item.name+'.lnk')
    if(Test-Path -LiteralPath $file){
        $existing=$shell.CreateShortcut($file)
        # Only replace prior setup-generated Colibri launchers; keep user-created links.
        if($existing.Description -notlike 'Start the local Colibri model server*' -and $existing.Description -ne 'Ubuntu PC Setup local AI shortcut'){
            Write-Warning "Keeping existing shortcut: $file";continue
        }
    }
    $link=$shell.CreateShortcut($file)
    $link.TargetPath=Join-Path $root 'venv\Scripts\pythonw.exe'
    $link.Arguments='"'+(Join-Path $root 'openwebui_desktop.py')+'" '+$item.action+' --root "'+$root+'"'
    $link.WorkingDirectory=$root
    $link.Description='Ubuntu PC Setup local AI shortcut'
    $link.IconLocation=Join-Path $root $item.icon
    $link.Save()
}
Write-Host 'Open WebUI installed. Open Colibri Serve, then Open WebUI. Create your local account on first launch.'
Write-Host 'After first sign-up, import and verify the complete skills using:'
Write-Host "& '$python' '$(Join-Path $root 'openwebui_skills.py')' import --root '$(Join-Path $root 'skill-repos')' --url http://127.0.0.1:8080"
Write-Host 'Existing OMP skills and Wikipedia have not been removed. Skill import must succeed before cleanup.'

# First-run account remains user-chosen; this shortcut completes authenticated imports.
$finish=Join-Path $desktop 'Finish Open WebUI Setup.lnk'
if(-not(Test-Path -LiteralPath $finish)){
    $link=$shell.CreateShortcut($finish)
    $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments='-NoProfile -File "'+(Join-Path $root 'Finish-OpenWebUI.ps1')+'" -Root "'+$root+'"'
    $link.WorkingDirectory=$root
    $link.Description='Import complete skills and connect local Wikipedia after account creation.'
    $link.Save()
}
