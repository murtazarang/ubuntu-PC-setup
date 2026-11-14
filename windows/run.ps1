# Short-entry launcher. Run from an elevated PowerShell on the Windows PC.
# Isolate parameters from the caller when invoked through Invoke-Expression.
& {
[CmdletBinding()]
param(
    [ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,
    [ValidateSet('Drivers','Desktop')][string]$Stage
)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This launcher requires Windows.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as administrator and run the launcher again.'
}
if (-not $Hardware) {
    Write-Host 'Choose your PC:'
    Write-Host '1. RTX 3080    2. Intel Arc B580    3. Two RTX 3060s'
    switch (Read-Host 'Enter 1, 2, or 3') {
        '1' { $Hardware = 'NvidiaSingle' }
        '2' { $Hardware = 'Intel' }
        '3' { $Hardware = 'NvidiaDual' }
        default { throw 'Invalid PC choice; nothing was installed.' }
    }
}
if (-not $Stage) {
    Write-Host 'Choose a stage:'
    Write-Host '1. Windows updates and GPU vendor app    2. Desktop setup (after reboot)'
    switch (Read-Host 'Enter 1 or 2') {
        '1' { $Stage = 'Drivers' }
        '2' { $Stage = 'Desktop' }
        default { throw 'Invalid stage choice; nothing was installed.' }
    }
}
# WinGet defaults to MSIX from PowerShell 7.6; support MSIX and MSI.
function Test-PowerShell7Candidate([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $version = @(& $Path -NoProfile -NonInteractive -Command '$PSVersionTable.PSVersion.Major' 2>$null)
        return $LASTEXITCODE -eq 0 -and $version.Count -eq 1 -and "$($version[0])" -match '^[0-9]+$' -and [int]$version[0] -ge 7
    } catch { return $false }
}
function Find-PowerShell7 {
    $command = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-PowerShell7Candidate $command.Source)) { return $command.Source }
    $msi = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if (Test-PowerShell7Candidate $msi) { return $msi }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        $packages = @(Get-AppxPackage -Name Microsoft.PowerShell -ErrorAction Stop | Sort-Object Version -Descending)
        foreach ($package in $packages) {
            if (-not $package.InstallLocation) { continue }
            $exe = Join-Path $package.InstallLocation 'pwsh.exe'
            if (Test-PowerShell7Candidate $exe) { return $exe }
        }
    }
    return $null
}
$candidate = Find-PowerShell7
if (-not $candidate) {
    & winget.exe install --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements --no-upgrade --disable-interactivity
    $code = '0x{0:X8}' -f ([long]$LASTEXITCODE -band 0xFFFFFFFFL)
    if ($code -notin @('0x00000000','0x8A150061','0x8A15010D')) { throw "PowerShell 7 installation failed ($code)." }
    $candidate = Find-PowerShell7
}
if (-not $candidate) { throw 'PowerShell 7 was not located after installation. Open PowerShell 7 from the Start menu as administrator and retry; if it is missing, check the WinGet installation output.' }
$dir = Join-Path $env:LOCALAPPDATA ('PC-Setup\Runs\' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $archive = Join-Path $dir 'setup.zip'
    $unpacked = Join-Path $dir 'files'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    $setup = Join-Path $unpacked 'ubuntu-PC-setup-main\windows\Setup.ps1'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'Downloaded archive does not contain Windows setup.' }
    Write-Host "Setup files and recovery helpers are saved at: $(Split-Path -Parent $setup)"
    & $candidate -NoProfile -ExecutionPolicy Bypass -File $setup -Stage $stage -Hardware $hardware
    if ($LASTEXITCODE -ne 0) { throw "Setup did not complete (exit $LASTEXITCODE); review its output before retrying." }
} finally {
    Write-Host "Setup files remain at: $dir"
}

} @args
