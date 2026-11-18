# Native Windows Colibri, built-in UI, and pinned hardware-specific model setup.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,[switch]$NoShortcut,[switch]$SkipModelDownload)
# A Windows shortcut directly runs upstream coli serve, not a separate launcher/UI.
function New-ColibriServeShortcut {
    param([string]$Python,[string]$Coli,[string]$Model,[string]$Hardware,[string]$Desktop,[string]$Icon,[switch]$Image)
    function Quote-Literal([string]$Value){return "'"+$Value.Replace("'","''")+"'"}
    $dual=if($Hardware -eq 'NvidiaDual' -and -not $Image){"`$env:COLI_VK_DEV2='auto'"}else{"Remove-Item Env:COLI_VK_DEV2 -ErrorAction SilentlyContinue"}
    $precision="Remove-Item Env:COLI_DENSE_BITS -ErrorAction SilentlyContinue; Remove-Item Env:COLI_DENSE_INT4 -ErrorAction SilentlyContinue"
    $port=if($Image){8001}else{8000}
    $uiPort=if($Image){8791}else{8790}
    $modelsRoot=Split-Path (Split-Path $Model -Parent) -Parent
    # Windows path components cannot contain a literal quote; quote each path
    # for Start-Process's native argument string, then quote that string for PS.
    $serverArguments='"'+$Coli+'" serve --host 127.0.0.1 --port '+$port+' --model "'+$Model+'"'
    $command="`$ErrorActionPreference='Stop'; `$env:COLI_VULKAN='1'; `$env:COLI_CUDA='0'; `$env:COLI_NO_OMP_TUNE='1'; $dual; $precision; foreach(`$p in @($port,$uiPort)){`$listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,`$p); try{`$listener.Start()}catch{throw ('Port '+`$p+' is already in use or unavailable. Leave existing servers untouched; close their own windows before retrying.')}finally{`$listener.Stop()}}; `$server=Start-Process -FilePath $(Quote-Literal $Python) -ArgumentList $(Quote-Literal $serverArguments) -PassThru; Write-Host 'The model server has its own terminal. Keep it and this UI terminal open; stop each with Ctrl+C when finished. The UI may open before the model finishes loading.'; & $(Quote-Literal $Python) $(Quote-Literal $Coli) ui --host 127.0.0.1 --port $uiPort --backend 'http://127.0.0.1:$port' --models-dir $(Quote-Literal $modelsRoot); if(`$LASTEXITCODE -ne 0){throw 'Colibri UI exited with an error; the separately started server may still be running.'}"
    if($Image){
        # The modern UI has no working image generation submit handler in v2.1.0.
        # Use upstream's image-capable bundled dashboard, as explicitly requested.
        $command="`$ErrorActionPreference='Stop'; `$env:COLI_VULKAN='1'; `$env:COLI_CUDA='0'; `$env:COLI_NO_OMP_TUNE='1'; $dual; $precision; & $(Quote-Literal $Python) $(Quote-Literal $Coli) web --host 127.0.0.1 --port $port --model $(Quote-Literal $Model); if(`$LASTEXITCODE -ne 0){throw 'Colibri image server exited with an error.'}"
    }
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $name=if($Image){'Colibri Serve Image.lnk'}else{'Colibri Serve.lnk'}
    $link=Join-Path $Desktop $name
    $shell=New-Object -ComObject WScript.Shell
    if(Test-Path -LiteralPath $link){
        Write-Warning "Keeping existing Serve shortcut at $link. Delete it and rerun setup to regenerate it."
        return
    }
    $shortcut=$shell.CreateShortcut($link)
    $shortcut.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $shortcut.Arguments='-NoProfile -NoExit -EncodedCommand '+$encoded
    $shortcut.WorkingDirectory=Split-Path $Coli -Parent
    $shortcut.IconLocation=$Icon
    $shortcut.Description='Start the local Colibri model server; keep its window open while using the UI.'
    $shortcut.Save()
}
function Test-ColibriOwnedMetadata {
    param($Conversion,[string]$Model)
    if(-not($Conversion.PSObject.Properties.Name -contains 'hashes')){throw 'Existing model lacks owned metadata hashes; preserving it.'}
    foreach($name in @('gguf.json','config.json','tokenizer.json')){
        if(-not($Conversion.hashes.PSObject.Properties.Name -contains $name)){throw "Missing ownership hash for $name; preserving model."}
    }
    foreach($property in $Conversion.hashes.PSObject.Properties){
        if($property.Name -match '[:/\\]' -or $property.Name -in @('.','..') -or [IO.Path]::GetFileName($property.Name) -ne $property.Name){throw 'Invalid model metadata manifest path.'}
        $owned=Join-Path $Model $property.Name
        if((Test-Path -LiteralPath $owned) -and ((Get-Item -LiteralPath $owned -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Model metadata link is not safe to rewrite.'}
        if(-not(Test-Path -LiteralPath $owned -PathType Leaf) -or (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash -ne $property.Value){throw "Model metadata was changed or removed; preserving it: $owned"}
    }
}
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$uv=(Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
$root=Join-Path $env:LOCALAPPDATA 'Colibri-PC-Setup'
$version='v2.1.0'
$profile='vulkan'
$release=Join-Path $root "$version-$profile"
$marker=Join-Path $release 'pc-setup.json'
if(Test-Path -LiteralPath $release){
    if(-not(Test-Path -LiteralPath $marker)){throw "Unrecognized/incomplete installation at $release. Preserving it; inspect before retrying."}
    $saved=Get-Content -LiteralPath $marker -Raw|ConvertFrom-Json
    if($saved.version -ne $version -or $saved.profile -ne $profile){throw 'Existing Colibri installation marker differs; preserving files.'}
}else{
    New-Item -ItemType Directory -Path $root -Force|Out-Null
    $stage=Join-Path $root ('staging-'+[guid]::NewGuid())
    New-Item -ItemType Directory -Path $stage|Out-Null
    $archives=@(@{Name="colibri-$version-windows-x86_64.zip";Hash='195ee0be129d563789f1ade2383e023bde5519230d6fb508516e63767ee85465'})
    try{
        foreach($asset in $archives){
            $zip=Join-Path $stage $asset.Name
            Invoke-WebRequest -Uri "https://github.com/JustVugg/colibri/releases/download/$version/$($asset.Name)" -OutFile $zip
            if((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $asset.Hash){throw 'Colibri archive checksum mismatch.'}
            Expand-Archive -LiteralPath $zip -DestinationPath (Join-Path $stage 'app') -Force
            Remove-Item -LiteralPath $zip
        }
        foreach($file in @('coli','ui\server.py','ui\index.html','qwenimage.exe')){if(-not(Test-Path -LiteralPath (Join-Path $stage "app\$file"))){throw "Colibri archive is missing $file"}}
        # uv-managed Python and dependencies; do not touch other Python environments.
        @{version=$version;profile=$profile;ready=$false}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $stage 'pc-setup.json') -Encoding utf8
        Move-Item -LiteralPath $stage -Destination $release
    }catch{throw "Colibri setup failed; partial files preserved at $stage or $release. $($_.Exception.Message)"}
}
# This stage is rerunnable after dependency/network failure; never clear the venv.
& $uv venv --no-project --allow-existing --python 3.12 (Join-Path $release 'venv')
if($LASTEXITCODE -ne 0){throw 'Colibri Python environment creation failed; rerun this installer.'}
& $uv pip install --python (Join-Path $release 'venv\Scripts\python.exe') numpy pillow
if($LASTEXITCODE -ne 0){throw 'Colibri local UI dependencies failed; rerun this installer.'}
@{version=$version;profile=$profile;ready=$true}|ConvertTo-Json|Set-Content -LiteralPath $marker -Encoding utf8
$settingsPath=Join-Path $root 'settings.json'
$models=Join-Path $env:USERPROFILE 'colibri-models'
if(Test-Path -LiteralPath $settingsPath){
    $previous=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json
    if($previous.models){$models=[string]$previous.models}
    if($previous.hardware -ne $Hardware){throw 'Existing Colibri hardware profile differs; preserving its settings.'}
}
@{version=$version;profile=$profile;hardware=$Hardware;release=$release;models=$models}|ConvertTo-Json|Set-Content -LiteralPath $settingsPath -Encoding utf8
# Exact pinned model artifacts are selected by the requested PC profile.
$modelKey=if($Hardware -eq 'NvidiaDual'){'flash-next-iq2-xs'}else{'dense27b'}
$modelRoot=Join-Path $models $modelKey
$source=Join-Path $modelRoot 'source'
$model=Join-Path $modelRoot 'model'
$python=Join-Path $release 'venv\Scripts\python.exe'
$coli=Join-Path $release 'app\coli'
if(-not $SkipModelDownload){
    $repoRoot=Split-Path $PSScriptRoot -Parent
    $manifest=Get-Content -LiteralPath (Join-Path $repoRoot 'colibri-models.json') -Raw|ConvertFrom-Json
    $entry=$manifest.$modelKey
    $conversionMarker=Join-Path $model '.pc-setup-conversion.json'
    $ready=$false
    if(Test-Path -LiteralPath $model){
        if((Get-Item -LiteralPath $model -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Model directory is a link/junction; preserving it rather than importing through it.'}
        if(-not(Test-Path -LiteralPath $conversionMarker)){throw "Unrecognized model output at $model; preserving it."}
        $conversion=Get-Content -LiteralPath $conversionMarker -Raw|ConvertFrom-Json
        if($conversion.revision -ne $entry.revision -or $conversion.key -ne $modelKey){throw 'Existing model conversion differs; preserving it.'}
        $ready=[bool]$conversion.ready
        if($ready){
            Test-ColibriOwnedMetadata -Conversion $conversion -Model $model
            $requiredFiles=@('gguf.json','config.json','tokenizer.json')
            foreach($required in $requiredFiles){
                $artifact=Join-Path $model $required
                if(-not(Test-Path -LiteralPath $artifact -PathType Leaf) -or (Get-Item -LiteralPath $artifact).Length -eq 0){throw "Prepared model artifact missing/empty: $artifact. Preserving remaining output."}
            }
        }
    }
    & $python (Join-Path $repoRoot 'download_colibri_model.py') --model $modelKey --destination $source --reserve-bytes 0
    if($LASTEXITCODE -ne 0){throw 'Model download/verification failed; files and partials are retained for rerun.'}
    # Re-import verified GGUF metadata on rerun so copied source paths are local.
    & {
        New-Item -ItemType Directory -Path $model -Force|Out-Null
        @{key=$modelKey;revision=$entry.revision;ready=$false}|ConvertTo-Json|Set-Content -LiteralPath $conversionMarker -Encoding utf8
        & $python $coli import (Join-Path $source $entry.first_shard) --out $model --mode link --no-mtp
        if($LASTEXITCODE -ne 0){throw 'Model import failed; source files retained.'}
        if(-not(Test-Path -LiteralPath (Join-Path $model 'gguf.json'))){throw 'Model import did not produce gguf.json.'}
        $hashes=@{}
        foreach($file in Get-ChildItem -LiteralPath $model -File){
            if($file.FullName -ne $conversionMarker){$hashes[$file.Name]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
        }
        @{key=$modelKey;revision=$entry.revision;ready=$true;hashes=$hashes}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $conversionMarker -Encoding utf8
    }
    $imageModel=Join-Path $models 'qwen-image-2.1\model'
    & $python (Join-Path $repoRoot 'download_colibri_model.py') --model qwen-image-2.1 --destination $imageModel --reserve-bytes 0
    if($LASTEXITCODE -ne 0){throw 'Image model download/verification failed; partial files retained for rerun.'}
    if(-not(Test-Path -LiteralPath (Join-Path $imageModel 'model_index.json'))){throw 'Image model layout missing model_index.json.'}
}else{Write-Warning 'Model download skipped explicitly: CI smoke mode; no model inference has been verified.'}
$desktop=[Environment]::GetFolderPath('Desktop')
if($desktop -and -not $NoShortcut){
    if(-not $SkipModelDownload){
        $icon=Join-Path $root 'colibri-serve.ico'
        Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\colibri\colibri-serve.ico') -Destination $icon -Force
        New-ColibriServeShortcut -Python $python -Coli $coli -Model $model -Hardware $Hardware -Desktop $desktop -Icon $icon
        $imageIcon=Join-Path $root 'colibri-serve-image.ico'
        Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) 'assets\colibri\colibri-serve-image.ico') -Destination $imageIcon -Force
        New-ColibriServeShortcut -Python $python -Coli $coli -Model $imageModel -Hardware $Hardware -Desktop $desktop -Icon $imageIcon -Image
    }

}
Write-Host "Colibri installed for $Hardware. Use Colibri Serve or Colibri Serve Image."
Write-Host 'Text opens native serve + modern ui. Image opens the upstream image-capable web dashboard. Stop the running server before switching models.'
Write-Host 'Windows upstream UI cannot switch the running model; see README for the upstream coli serve command.'
