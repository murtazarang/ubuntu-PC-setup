# Short-entry launcher. Run from an elevated PowerShell on the Windows PC.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'This launcher requires Windows.' }
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as administrator and run the launcher again.'
}
Write-Host 'Choose your PC:'
Write-Host '1. RTX 3080    2. Intel Arc B580    3. Two RTX 3060s'
switch (Read-Host 'Enter 1, 2, or 3') {
    '1' { $hardware = 'NvidiaSingle' }
    '2' { $hardware = 'Intel' }
    '3' { $hardware = 'NvidiaDual' }
    default { throw 'Invalid PC choice; nothing was installed.' }
}
Write-Host 'Choose a stage:'
Write-Host '1. Windows updates and GPU vendor app    2. Desktop setup (after reboot)'
switch (Read-Host 'Enter 1 or 2') {
    '1' { $stage = 'Drivers' }
    '2' { $stage = 'Desktop' }
    default { throw 'Invalid stage choice; nothing was installed.' }
}
$pwsh = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue
if (-not $pwsh) {
    & winget.exe install --id Microsoft.PowerShell --exact --source winget --accept-source-agreements --accept-package-agreements --no-upgrade --disable-interactivity
    $code = '0x{0:X8}' -f ([long]$LASTEXITCODE -band 0xFFFFFFFFL)
    if ($code -notin @('0x00000000','0x8A150061','0x8A15010D')) { throw "PowerShell 7 installation failed ($code)." }
    $candidate = Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
} else { $candidate = $pwsh.Source }
if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { throw 'PowerShell 7 was not found; reopen the terminal and retry.' }
$dir = Join-Path $env:TEMP ('pc-setup-' + [guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $dir | Out-Null
try {
    $archive = Join-Path $dir 'setup.zip'
    $unpacked = Join-Path $dir 'files'
    Invoke-WebRequest -Uri 'https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $unpacked
    $setup = Join-Path $unpacked 'ubuntu-PC-setup-main\windows\Setup.ps1'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw 'Downloaded archive does not contain Windows setup.' }
    & $candidate -NoProfile -ExecutionPolicy Bypass -File $setup -Stage $stage -Hardware $hardware
    if ($LASTEXITCODE -ne 0) { throw "Setup did not complete (exit $LASTEXITCODE); review its output before retrying." }
} finally {
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
