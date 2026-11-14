# Set up a local model on the requested NVIDIA or Intel GPU.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
if ($Hardware -like 'Nvidia*') {
    $smi = Get-Command nvidia-smi.exe -CommandType Application -ErrorAction Stop
    $gpus = @(& $smi.Source --query-gpu=index --format=csv,noheader)
    if ($LASTEXITCODE -ne 0) { throw 'NVIDIA driver is not ready; reboot and verify nvidia-smi.' }
    $expected = if ($Hardware -eq 'NvidiaDual') { 2 } else { 1 }
    if ($gpus.Count -ne $expected) { throw "Expected $expected NVIDIA GPU(s), detected $($gpus.Count)." }
    $strata = Get-Command strata.cmd -CommandType Application -ErrorAction SilentlyContinue
    if (-not $strata) {
        $installer = Join-Path $env:TEMP 'strata-install.ps1'
        Invoke-WebRequest -Uri 'https://github.com/Niko1221/Strata/releases/latest/download/install.ps1' -OutFile $installer
        & $installer
        if ($LASTEXITCODE -ne 0) { throw 'Strata installer failed.' }
        $env:Path = [Environment]::GetEnvironmentVariable('Path','User') + ';' + [Environment]::GetEnvironmentVariable('Path','Machine')
        $strata = Get-Command strata.cmd -CommandType Application -ErrorAction Stop
    }
    $argsList = @('launch','--family','qwen','--context','32k','--access','local','--vision','off','--yes','--no-tui')
    if ($Hardware -eq 'NvidiaDual') { $argsList += @('--model','iq3_xxs','--gpu-roles','0=main,1=helper') }
    else { $argsList += @('--model','iq2_xs') }
    & $strata.Source @argsList
    if ($LASTEXITCODE -ne 0) { throw 'Strata launch failed. Check the driver and the Strata logs.' }
    $port = '8080'
} else {
    $appRoot = Join-Path $env:LOCALAPPDATA 'XeStrata-Setup'
    $cliExecutables = @(Get-ChildItem -Path $appRoot -Filter 'xestrata-cli.exe' -File -Recurse -ErrorAction SilentlyContinue)
    if ($cliExecutables.Count -gt 1) { throw "Multiple XeStrata CLI executables found under $appRoot; resolve before retrying." }
    $exe = if ($cliExecutables.Count -eq 1) { $cliExecutables[0].FullName } else { $null }
    if (-not $exe) {
        if (Test-Path -LiteralPath $appRoot) { throw "Not overwriting incomplete XeStrata path $appRoot; inspect it before retrying." }
        $sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
        if (-not (Test-Path -LiteralPath $sevenZip)) { throw 'Install 7-Zip before XeStrata.' }
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/MistVVK/XeStrata/releases/latest'
        $asset = @($release.assets | Where-Object { $_.name -match '^XeStrata-.*-windows-x64\.7z$' })
        $sums = @($release.assets | Where-Object { $_.name -eq 'SHA256SUMS' })
        if ($asset.Count -ne 1 -or $sums.Count -ne 1) { throw 'Could not identify XeStrata Windows release and checksums.' }
        $temp = Join-Path $env:TEMP ('xestrata-' + [guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $temp | Out-Null
        try {
            $archive = Join-Path $temp $asset[0].name
            $sumFile = Join-Path $temp 'SHA256SUMS'
            Invoke-WebRequest -Uri $asset[0].browser_download_url -OutFile $archive
            Invoke-WebRequest -Uri $sums[0].browser_download_url -OutFile $sumFile
            $line = @(Get-Content -LiteralPath $sumFile | Where-Object { $_ -match ('\s\*?' + [regex]::Escape($asset[0].name) + '$') })
            if ($line.Count -ne 1 -or $line[0] -notmatch '^([0-9a-fA-F]{64})\s') { throw 'XeStrata checksum not found.' }
            $expectedHash = $Matches[1]
            if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) { throw 'XeStrata checksum mismatch.' }
            New-Item -ItemType Directory -Path $appRoot -Force | Out-Null
            & $sevenZip x "-o$appRoot" $archive -y
            if ($LASTEXITCODE -ne 0) { throw 'XeStrata extraction failed.' }
        } finally { Remove-Item -LiteralPath $temp -Force -Recurse -ErrorAction SilentlyContinue }
    }
    $cliExecutables = @(Get-ChildItem -Path $appRoot -Filter 'xestrata-cli.exe' -File -Recurse -ErrorAction SilentlyContinue)
    if ($cliExecutables.Count -ne 1) { throw "Expected one XeStrata CLI executable under $appRoot; found $($cliExecutables.Count)." }
    $exe = $cliExecutables[0].FullName
    # Upstream's Windows CLI accepts the package's normal setup options.
    $xe = Start-Process -FilePath $exe -ArgumentList @('--setup','--family','gyro','--model','Gyro-S','--context','32768','--vision','no','--yes') -PassThru
    Write-Host 'XeStrata is preparing its model in a separate window. Follow any prompts there.'
    $port = '8095'
}
# The first load can take several minutes.
$ready = $false
for ($i = 0; $i -lt 180; $i++) {
    try {
        $null = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/models" -TimeoutSec 3
        $ready = $true
        break
    } catch { Start-Sleep -Seconds 5 }
}
if (-not $ready) { throw "Model endpoint on $port did not become ready. Start it and rerun Connect-LocalModel.ps1 -Port $port." }
& (Join-Path $PSScriptRoot 'Connect-LocalModel.ps1') -Port $port
