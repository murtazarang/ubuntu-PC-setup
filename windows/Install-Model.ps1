# Set up a local model on the requested NVIDIA or Intel GPU.
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,
    [ValidateRange(1,1440)][int]$ModelReadyTimeoutMinutes = 30
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Discover an existing Strata command before considering installation, including
# PATH entries added by an earlier installation in another terminal.
$env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine')) | Where-Object { $_ }) -join ';'
# Upstream --no-start completes preparation before returning; downloading a 58 GB
# model must not consume the endpoint startup timeout.
function Assert-XeStrataIdle {
    # A matching executable does not prove model identity. Never reuse or stop an
    # existing server/setup, even if its API happens to answer on the desired port.
    if (@(Get-Process -Name 'xestrata-cli' -ErrorAction SilentlyContinue).Count -gt 0) {
        throw 'XeStrata is already running or preparing a model. Leave it running, or close it yourself before retrying; this setup will not change or duplicate it.'
    }
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -eq 8095 })
    if ($listeners.Count -gt 0) {
        throw 'Port 8095 is already in use. This setup cannot verify the model there and will not modify or reuse that server.'
    }
}
# Upstream --describe reports installed model configs without entering setup.
# https://github.com/MistVVK/XeStrata/blob/main/setup.py
function Test-XeStrataNeedsPreparation {
    param([Parameter(Mandatory=$true)][string]$Executable)
    $raw = (& $Executable --describe | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect XeStrata model inventory; refusing to change an existing installation.' }
    try { $inventory = $raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'XeStrata returned invalid model inventory; refusing to run setup.' }
    if ($null -eq $inventory -or -not $inventory.PSObject.Properties['installed'] -or
        $null -eq $inventory.installed -or $inventory.installed -isnot [System.Array]) {
        throw 'XeStrata inventory has no valid installed-model array; refusing to run setup.'
    }
    $installed = @($inventory.installed)
    if ($installed.Count -eq 0) { return $true }
    # Without --setup/--model/--family, upstream starts its newest config.
    # Only a single matching config is unambiguous; never rewrite another model
    # or change a user's existing context/settings merely to rerun this script.
    if ($installed.Count -ne 1) {
        throw 'XeStrata has multiple saved models. Preserving all settings; start the intended Gyro-S model in XeStrata, then run Connect-LocalModel.ps1 -Port 8095 separately.'
    }
    $model = $installed[0]
    foreach ($key in @('family','model_name','context','config')) {
        if ($null -eq $model -or -not $model.PSObject.Properties[$key]) { throw 'XeStrata model inventory is incomplete; refusing to run setup.' }
    }
    if ($model.family -ne 'gyro' -or $model.model_name -ne 'qwen3.8-flash-next-gyro-gyro-s' -or $model.context -ne 32768 -or
        [string]::IsNullOrWhiteSpace([string]$model.config)) {
        throw 'XeStrata has an existing model or context different from this setup. Preserving it; manage the desired model in XeStrata and connect it separately.'
    }
    Write-Host 'Existing XeStrata Gyro-S configuration found; skipping model preparation and preserving its settings.'
    return $false
}
function Start-XeStrataModel {
    param([Parameter(Mandatory=$true)][string]$Executable)
    Assert-XeStrataIdle
    if (Test-XeStrataNeedsPreparation -Executable $Executable) {
        Write-Host 'Preparing XeStrata Gyro-S. The large download may take hours; progress appears below.'
        & $Executable --setup --family gyro --model Gyro-S --context 32768 --vision no --yes --no-start | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "XeStrata preparation failed (exit $LASTEXITCODE). Rerun after correcting the reported error." }
        # Verify what was actually prepared before relying on newest-config startup.
        if (Test-XeStrataNeedsPreparation -Executable $Executable) { throw 'XeStrata preparation returned without a saved model configuration.' }
    }
    Assert-XeStrataIdle
    # --model would enter setup again. Upstream --yes starts the newest saved config,
    # which the inventory check above verified as the only matching configuration.
    return Start-Process -FilePath $Executable -ArgumentList @('--yes','--port','8095') -PassThru
}
$xe = $null
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
        # A successful script may leave a nonzero native exit from an upstream fallback.
        if (-not $?) { throw 'Strata installer failed.' }
        $env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine')) | Where-Object { $_ }) -join ';'
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
    $xe = Start-XeStrataModel -Executable $exe
    Write-Host 'XeStrata runs in a separate window. Keep that window open while using the model.'
    $port = '8095'
}
# This timeout begins after preparation, not while downloading the model.
$ready = $false
$deadline = [DateTime]::UtcNow.AddMinutes($ModelReadyTimeoutMinutes)
while ([DateTime]::UtcNow -lt $deadline) {
    if ($null -ne $xe) {
        $xe.Refresh()
        if ($xe.HasExited) { throw "XeStrata exited before readiness (exit $($xe.ExitCode)); inspect its window/logs before retrying." }
    }
    try {
        $null = Invoke-RestMethod -Uri "http://127.0.0.1:$port/v1/models" -TimeoutSec 3
        $ready = $true
        break
    } catch { Start-Sleep -Seconds 5 }
}
if (-not $ready) { throw "Model endpoint on $port did not become ready within $ModelReadyTimeoutMinutes minutes. The process was left running; do not launch another copy. Inspect the model window, then rerun this stage or Connect-LocalModel.ps1 -Port $port when ready." }
& (Join-Path $PSScriptRoot 'Connect-LocalModel.ps1') -Port $port

