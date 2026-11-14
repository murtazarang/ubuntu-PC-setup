#Requires -Version 5.1
# Direct entry point: irm https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/aida64_display/install.ps1 | iex
# The child scope prevents validation attributes leaking into the caller's session.
& {
    [CmdletBinding()]
    param(
        [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'),
        [ValidateSet(0,90,180,270)][int]$Rotation = 270,
        [switch]$SetupOnly
    )
    $ErrorActionPreference = 'Stop'
    if (-not (Get-Command uv.exe -ErrorAction SilentlyContinue)) {
        throw 'uv is required. Run the PC setup prerequisites or install uv from https://docs.astral.sh/uv/getting-started/installation/ and reopen PowerShell.'
    }
    $InstallDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($InstallDir)
    # Retain the downloaded scripts, including after a failure, for diagnosis/resume.
    $runDir = Join-Path $InstallDir ('setup-runs\' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    try {
        Write-Host 'Downloading the AX206 setup from GitHub main...'
        $archive = Join-Path $runDir 'setup.zip'
        Invoke-WebRequest -Uri 'https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip' -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath $runDir
        $scripts = Join-Path $runDir 'ubuntu-PC-setup-main\windows\aida64_display'
        foreach ($name in @('Setup.ps1','Run.ps1','panel.py','portrait.yaml','LICENSE')) {
            if (-not (Test-Path -LiteralPath (Join-Path $scripts $name) -PathType Leaf)) {
                throw "Downloaded archive is missing AX206 file: $name"
            }
        }
        & (Join-Path $scripts 'Setup.ps1') -InstallDir $InstallDir
        # Only our launcher is updated. Setup preserves an existing portrait.yaml.
        Copy-Item -LiteralPath (Join-Path $scripts 'Run.ps1') -Destination (Join-Path $InstallDir 'Run.ps1') -Force
        Remove-Item -LiteralPath $archive
        $quotedDir = $InstallDir.Replace("'", "''")
        Write-Host 'Setup complete. Start the display again without downloading:'
        Write-Host "& '$quotedDir\Run.ps1' -InstallDir '$quotedDir' -Rotation $Rotation"
        Write-Host 'To inspect USB resolution or diagnose access:'
        Write-Host "& '$quotedDir\Run.ps1' -InstallDir '$quotedDir' -Action Info"
        if (-not $SetupOnly) {
            Write-Host 'Starting the portrait display. Keep this terminal open; Ctrl+C stops it.'
            & (Join-Path $InstallDir 'Run.ps1') -InstallDir $InstallDir -Rotation $Rotation
        }
    } catch {
        Write-Host "Downloaded setup files remain at: $runDir"
        throw
    }
} @args
