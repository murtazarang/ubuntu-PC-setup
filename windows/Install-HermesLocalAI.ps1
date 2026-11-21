#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('NvidiaSingle','NvidiaDual','Intel')][string]$Hardware,
    [string]$ArchiveDirectory = (Join-Path $env:LOCALAPPDATA 'OpenZIM\archives')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'Native Windows is required.' }
$repo = Split-Path -Parent $PSScriptRoot
$root = Join-Path $env:LOCALAPPDATA 'PCSetup\local-ai'
$scripts = Join-Path $root 'scripts'
New-Item -ItemType Directory -Force -Path $scripts | Out-Null
Copy-Item -Path (Join-Path $repo 'local_ai\*.py') -Destination $scripts
$wikiSkill = Join-Path $scripts 'offline-wikipedia'
New-Item -ItemType Directory -Force -Path $wikiSkill | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'local_ai\offline-wikipedia\SKILL.md') -Destination $wikiSkill
$localSetup = Join-Path $scripts 'local_setup.py'
$homePath = Join-Path $root 'hermes-home'
$source = Join-Path $homePath 'hermes-agent'
$commit = 'caafe5389ae585ef77387a962aee05b1bcf17029'
$uvCommand = Get-Command uv.exe -CommandType Application -ErrorAction Stop
$uv = $uvCommand.Source
$env:Path = (@($env:Path, [Environment]::GetEnvironmentVariable('Path','Machine'), [Environment]::GetEnvironmentVariable('Path','User')) -join ';')
$git = (Get-Command git.exe -CommandType Application -ErrorAction Stop).Source
$installed = $null
if (Test-Path -LiteralPath (Join-Path $source '.git')) {
    $installed = (& $git -C $source rev-parse HEAD)
    if ($LASTEXITCODE -ne 0) { throw 'Could not identify the managed Hermes checkout.' }
}
function Find-ManagedHermes {
    foreach ($name in 'hermes.exe','hermes.cmd') {
        $path = Join-Path $source ".hermes\bin\$name"
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
}
$hermes = Find-ManagedHermes
if (-not $hermes -or $installed -ne $commit) {
    if ($installed) {
        $diff = & $git -C $source status --porcelain --untracked-files=no
        if ($LASTEXITCODE -ne 0 -or $diff) { throw 'Local Hermes source modifications were not overwritten.' }
    }
    $installer = Join-Path $root 'hermes-install.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/NousResearch/hermes-agent/$commit/scripts/install.ps1" -OutFile $installer
    $installerOverrides = @{}
    $overrideKeys = @('HERMES_REPO_URL','HERMES_RUNTIME_DIR','HERMES_INSTALL_CHANNEL')
    try {
        foreach ($key in $overrideKeys) {
            $installerOverrides[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, $null, 'Process')
        }
        & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $installer -HermesHome $homePath -InstallDir $source -Commit $commit -NonInteractive -SkipBrowser -SkipComputerUse
        if ($LASTEXITCODE -ne 0) { throw "Official Hermes installer failed (exit $LASTEXITCODE)." }
    } finally {
        foreach ($key in $installerOverrides.Keys) { [Environment]::SetEnvironmentVariable($key, $installerOverrides[$key], 'Process') }
    }
    $hermes = Find-ManagedHermes
}
$installed = & $git -C $source rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $installed -ne $commit -or -not $hermes) { throw 'Managed Hermes release or launcher is missing.' }

& $uv python install --no-bin --no-registry 3.12
if ($LASTEXITCODE -ne 0) { throw 'Could not provision managed Python 3.12 for the launcher.' }
$python = (& $uv python find --managed-python --no-project 3.12 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Managed Python 3.12 is unavailable.' }

& (Join-Path $PSScriptRoot 'Install-Reference.ps1') -ArchiveDirectory $ArchiveDirectory
$record = Join-Path $env:LOCALAPPDATA 'OpenZIM\reference.json'
$bridge = (Get-Content -Raw -LiteralPath $record | ConvertFrom-Json).bridge
& $uv run --no-project --python $python --with 'PyYAML==6.0.3' python $localSetup configure --root $root --profile $Hardware --hermes $hermes --bridge $bridge --reference $record
if ($LASTEXITCODE -ne 0) { throw 'Local AI configuration failed; no shortcuts were created.' }
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
if (-not $desktop -or -not (Test-Path -LiteralPath $desktop -PathType Container)) { throw 'This Windows account has no accessible desktop.' }
$wsh = New-Object -ComObject WScript.Shell
foreach ($action in 'start','stop') {
    $title = if ($action -eq 'start') { 'Start Local AI' } else { 'Stop Local AI' }
    $linkPath = Join-Path $desktop "$title.lnk"
    $arguments = '"{0}" {1} --root "{2}" --profile {3}' -f $localSetup,$action,$root,$Hardware
    if (Test-Path -LiteralPath $linkPath) {
        $link = $wsh.CreateShortcut($linkPath)
        if ($link.Description -ne 'Ubuntu PC Setup Hermes local AI shortcut' -or $link.Arguments -notlike "*$localSetup*") {
            throw "Unrelated shortcut preserved: $linkPath"
        }
    }
    $link = $wsh.CreateShortcut($linkPath)
    $link.TargetPath = $python
    $link.Arguments = $arguments
    $link.WorkingDirectory = $env:USERPROFILE
    $link.Description = 'Ubuntu PC Setup Hermes local AI shortcut'
    $link.Save()
}
Write-Host 'Installed. Click Start Local AI on the desktop; Stop Local AI frees the model memory.'
