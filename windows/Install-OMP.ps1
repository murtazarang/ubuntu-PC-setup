# Install the publisher's native Windows build of Oh My Pi, for the current user.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# Refresh before discovery: an older terminal may not see a previous install.
$env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine')) | Where-Object { $_ }) -join ';'
function Find-ExistingOmp {
    # OMP's official source installer uses bun, which may expose omp.cmd.
    # This setup's downstream scripts require omp.exe; never replace that source
    # installation just because the binary-only lookup cannot see it.
    $active = Get-Command omp -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($active) {
        if ([IO.Path]::GetExtension($active.Source) -ine '.exe') {
            throw "Existing OMP installation found at $($active.Source). It was preserved. This setup currently requires omp.exe for downstream configuration; do not reinstall automatically. Use your existing OMP installation, or explicitly choose a binary installation before retrying."
        }
        return $active
    }
    $binary = Get-Command omp.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($binary) { return $binary }
    # Official installer default/override, not a recursive filesystem guess.
    # https://github.com/can1357/oh-my-pi/blob/main/scripts/install.ps1
    $directory = if ($env:PI_INSTALL_DIR) { $env:PI_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'omp' }
    $candidate = Join-Path $directory 'omp.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $env:Path = $directory + ';' + $env:Path
        return [pscustomobject]@{ Source = $candidate }
    }
    return $null
}
$omp = Find-ExistingOmp
if (-not $omp) {
    $tempFile = Join-Path $env:TEMP ('omp-installer-' + [guid]::NewGuid().ToString() + '.ps1')
    try {
        Invoke-WebRequest -Uri 'https://omp.sh/install.ps1' -OutFile $tempFile
        & $tempFile -Binary
        if (-not $?) { throw 'Oh My Pi installer failed.' }
    } finally { Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue }
    $env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable('Path','User'), [Environment]::GetEnvironmentVariable('Path','Machine')) | Where-Object { $_ }) -join ';'
    $omp = Find-ExistingOmp
}
if (-not $omp) { throw 'Oh My Pi is not on PATH after installation. Open a new terminal and retry.' }
& $omp.Source --version
if ($LASTEXITCODE -ne 0) { throw 'Oh My Pi was installed but did not start.' }
