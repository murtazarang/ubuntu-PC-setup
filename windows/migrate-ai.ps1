# Existing-PC AI-only entry point: irm <raw GitHub URL>/migrate-ai.ps1 | iex
& {
[CmdletBinding()]
param([ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,[string]$ArchiveDirectory)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'Native Windows is required.'}
if(-not $Hardware){
    Write-Host 'Choose your existing PC: 1 RTX3080, 2 ArcB580, 3 dualRTX3060'
    switch(Read-Host 'Enter 1, 2, or 3'){'1'{$Hardware='NvidiaSingle'}'2'{$Hardware='Intel'}'3'{$Hardware='NvidiaDual'}default{throw 'Invalid PC choice; no changes made.'}}
}
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

$candidate=Find-PowerShell7
if(-not $candidate){throw 'Existing setup requires PowerShell 7. Open its installed terminal and retry; this AI-only migration does not install system packages.'}
$dir=Join-Path $env:LOCALAPPDATA ('PC-Setup\AI-Migration\'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $dir|Out-Null
try{
    $archive=Join-Path $dir 'setup.zip'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/murtazarang/ubuntu-PC-setup/archive/refs/heads/main.zip' -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $dir 'files')
    $script=Join-Path $dir 'files\ubuntu-PC-setup-main\windows\Migrate-AI.ps1'
    if(-not(Test-Path -LiteralPath $script -PathType Leaf)){throw 'Downloaded package lacks the AI-only migration script.'}
    $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$script,'-Hardware',$Hardware)
    if($ArchiveDirectory){$arguments+=@('-ArchiveDirectory',$ArchiveDirectory)}
    & $candidate @arguments
    if($LASTEXITCODE -ne 0){throw "AI migration stopped (exit $LASTEXITCODE). Read the error; setup files remain at $dir."}
}finally{Write-Host "AI migration recovery files remain at $dir"}
} @args
