# Install the publisher's native Windows build of Oh My Pi, for the current user.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$omp = Get-Command omp.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $omp) {
    $tempFile = Join-Path $env:TEMP ('omp-installer-' + [guid]::NewGuid().ToString() + '.ps1')
    try {
        Invoke-WebRequest -Uri 'https://omp.sh/install.ps1' -OutFile $tempFile
        & $tempFile -Binary
        if (-not $?) { throw 'Oh My Pi installer failed.' }
    } finally { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
    $env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine')) | Where-Object { $_ }) -join ';'
    $omp = Get-Command omp.exe -CommandType Application -ErrorAction SilentlyContinue
}
if (-not $omp) { throw 'Oh My Pi is not on PATH after installation. Open a new terminal and retry.' }
& $omp.Source --version
if ($LASTEXITCODE -ne 0) { throw 'Oh My Pi was installed but did not start.' }
