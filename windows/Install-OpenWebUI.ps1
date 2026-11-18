# Native Windows only. No OMP, Docker, WSL, cloud account or network exposure.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$colibri=Get-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup\settings.json') -Raw|ConvertFrom-Json
# PyTorch official Windows/Linux 2.9.1 CUDA12.8 wheels; source-matched WebUI CUDA path.
$TorchBackend=if($colibri.hardware -eq 'Intel'){'cpu'}else{'cu128'}
$embeddingModel='BAAI/bge-small-en-v1.5'
$rerankingModel='cross-encoder/ms-marco-MiniLM-L6-v2'
$uv=(Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
$root=Join-Path $env:LOCALAPPDATA 'OpenWebUI-PC-Setup'
New-Item -ItemType Directory -Path $root -Force|Out-Null
$python=Join-Path $root 'venv\Scripts\python.exe'
& $uv venv --no-project --allow-existing --python 3.11 (Join-Path $root 'venv')
if($LASTEXITCODE -ne 0){throw 'Open WebUI Python environment creation failed.'}
# CUDA supporting models are authorized. Exact backend must match tested driver compatibility.
$installHelp=(& $uv pip install --help | Out-String)
if($LASTEXITCODE -ne 0 -or $installHelp -notmatch '--torch-backend'){throw 'Installed uv does not support --torch-backend. Update uv using its installation method, then rerun.'}
if($colibri.hardware -eq 'Intel'){
    # CPU torch supplies import/export utilities only. Retrieval inference is explicitly OpenVINO B580 GPU.
    & $uv pip install --torch-backend cpu --python $python 'open-webui==0.13.4' 'torch==2.9.1' 'torchvision==0.24.1' 'psutil==7.2.2' 'sentence-transformers[openvino]==5.5.1' 'optimum-intel[openvino]==2.2.0' 'openvino==2026.4.1'
}else{
    & $uv pip install --torch-backend cu128 --python $python 'open-webui==0.13.4' 'torch==2.9.1' 'torchvision==0.24.1' 'psutil==7.2.2' 'sentence-transformers==5.5.1'
}
if($LASTEXITCODE -ne 0){throw 'Open WebUI dependencies failed. Rerun to retry; existing data is retained.'}
Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'openwebui_gpu.py') -Destination $root -Force
if($colibri.hardware -eq 'Intel'){
    $gpuJson=& $python (Join-Path $root 'openwebui_gpu.py') detect-openvino
    if($LASTEXITCODE -ne 0){throw 'B580 OpenVINO GPU detection failed. No CPU fallback.'}
    $gpuEnvironment=$gpuJson|ConvertFrom-Json
    $probeCode="import json,os,subprocess,sys; env=os.environ.copy(); env.update(json.loads(sys.argv[2])); env['DATA_DIR']=sys.argv[5]; env.update(RAG_EMBEDDING_MODEL=sys.argv[3],RAG_RERANKING_MODEL=sys.argv[4],RAG_EMBEDDING_ENGINE='',RAG_RERANKING_ENGINE='',ENABLE_RAG_HYBRID_SEARCH='true',CHUNK_SIZE='400',CHUNK_OVERLAP='50',RAG_TEXT_SPLITTER='token_transformers',RAG_TOKENIZER_MODEL=sys.argv[3],RAG_EMBEDDING_QUERY_PREFIX='Represent this sentence for searching relevant passages: ',RAG_EMBEDDING_CONTENT_PREFIX=''); subprocess.run([sys.executable,sys.argv[1],'probe-openvino','--embedding-model',sys.argv[3],'--reranking-model',sys.argv[4]],env=env,check=True)"
    & $python -c $probeCode (Join-Path $root 'openwebui_gpu.py') ($gpuEnvironment|ConvertTo-Json -Compress) $embeddingModel $rerankingModel (Join-Path $root 'data')
    if($LASTEXITCODE -ne 0){throw 'Native Open WebUI retrieval inference did not verify on B580 GPU. No CPU fallback.'}
}else{
    & $python -c "import torch; assert torch.cuda.is_available(), 'CUDA unavailable; no CPU fallback. Check NVIDIA driver/CUDA wheel compatibility.'; print('CUDA supporting-model device:', torch.cuda.get_device_name(0))"
    if($LASTEXITCODE -ne 0){throw 'Open WebUI CUDA verification failed. No CPU fallback was configured.'}
    $gpuEnvironment=[pscustomobject]@{USE_CUDA_DOCKER='true';USE_SLIM_DOCKER='false';SENTENCE_TRANSFORMERS_BACKEND='torch';SENTENCE_TRANSFORMERS_CROSS_ENCODER_BACKEND='torch';SENTENCE_TRANSFORMERS_MODEL_KWARGS='{}';SENTENCE_TRANSFORMERS_CROSS_ENCODER_MODEL_KWARGS='{}'}
}
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
$managedEnvironment=@{WEBUI_AUTH='true';OPENAI_API_BASE_URL='http://127.0.0.1:8000/v1';OPENAI_API_KEY='local-colibri';ENABLE_OLLAMA_API='false';ENABLE_WEB_SEARCH='true';WEB_SEARCH_ENGINE='duckduckgo';RAG_EMBEDDING_ENGINE='';RAG_RERANKING_ENGINE='';ENABLE_RAG_HYBRID_SEARCH='true';CHUNK_SIZE='400';CHUNK_OVERLAP='50';RAG_TEXT_SPLITTER='token_transformers';RAG_TOKENIZER_MODEL=$embeddingModel;RAG_EMBEDDING_QUERY_PREFIX='Represent this sentence for searching relevant passages: ';RAG_EMBEDDING_CONTENT_PREFIX='';RAG_EMBEDDING_MODEL=$embeddingModel;RAG_RERANKING_MODEL=$rerankingModel;RAG_EMBEDDING_MODEL_TRUST_REMOTE_CODE='false';RAG_RERANKING_MODEL_TRUST_REMOTE_CODE='false'}
foreach($property in $gpuEnvironment.PSObject.Properties){$managedEnvironment[$property.Name]=[string]$property.Value}
if($colibri.hardware -ne 'Intel'){
    $probeCode="import json,os,subprocess,sys; env=os.environ.copy(); env.update(json.loads(sys.argv[2])); env['DATA_DIR']=sys.argv[5]; subprocess.run([sys.executable,sys.argv[1],'probe-cuda','--embedding-model',sys.argv[3],'--reranking-model',sys.argv[4]],env=env,check=True)"
    & $python -c $probeCode (Join-Path $root 'openwebui_gpu.py') ($managedEnvironment|ConvertTo-Json -Compress) $embeddingModel $rerankingModel (Join-Path $root 'data')
    if($LASTEXITCODE -ne 0){throw 'Native Open WebUI embedding/reranking CUDA inference did not verify. No CPU fallback.'}
}

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
        webui_environment=$managedEnvironment
    }|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $configPath -Encoding utf8
}else{Write-Host "Preserving existing runtime settings: $configPath"}
foreach($icon in @('colibri-serve.ico','colibri-serve-image.ico')){
    Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) ('assets\colibri\'+$icon)) -Destination (Join-Path $root $icon) -Force
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'openwebui_desktop.py') -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Finish-OpenWebUI.ps1') -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Remove-VerifiedOMP.ps1') -Destination $root -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Remove-OMPBinary.ps1') -Destination $root -Force
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
$finishTarget=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$oldFinishArguments='-NoProfile -File "'+(Join-Path $root 'Finish-OpenWebUI.ps1')+'" -Root "'+$root+'"'
$updateFinish=-not(Test-Path -LiteralPath $finish)
if(-not $updateFinish){
    $previousFinish=$shell.CreateShortcut($finish)
    $updateFinish=($previousFinish.TargetPath -ieq $finishTarget -and $previousFinish.Arguments -ceq $oldFinishArguments -and $previousFinish.Description -ceq 'Import complete skills and connect local Wikipedia after account creation.')
}
if($updateFinish){
    $link=$shell.CreateShortcut($finish)
    $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $root 'Finish-OpenWebUI.ps1')+'" -Root "'+$root+'"'
    $link.WorkingDirectory=$root
    $link.Description='Import complete skills and connect local Wikipedia after account creation.'
    $link.Save()
}
