# Native Windows Colibri with its built-in browser UI. No model downloads.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,[switch]$NoShortcut)
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
        foreach($file in @('coli','ui\server.py','ui\index.html')){if(-not(Test-Path -LiteralPath (Join-Path $stage "app\$file"))){throw "Colibri archive is missing $file"}}
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
$desktop=[Environment]::GetFolderPath('Desktop')
if($desktop -and -not $NoShortcut){
    $link=Join-Path $desktop 'Colibri UI.lnk'
    if(-not(Test-Path -LiteralPath $link)){
        $shell=New-Object -ComObject WScript.Shell
        $shortcut=$shell.CreateShortcut($link)
        $shortcut.TargetPath=Join-Path $release 'venv\Scripts\python.exe'
        $shortcut.Arguments='"'+(Join-Path $release 'app\coli')+'" ui --host 127.0.0.1 --port 8790 --backend http://127.0.0.1:8000 --models-dir "'+$models+'"'
        $shortcut.WorkingDirectory=$root
        $shortcut.Save()
    }
}
Write-Host "Colibri installed for $Hardware. Open the Colibri UI desktop shortcut."
Write-Host 'Use Models in the UI to download a model. No model was downloaded by this installer.'
Write-Host 'Windows upstream UI cannot switch the running model; see README for the upstream coli serve command.'
