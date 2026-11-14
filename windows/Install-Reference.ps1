# Install and register offline Wikipedia and OpenZIM MCP for the current user.
[CmdletBinding()]
param(
    [string]$ArchiveDirectory = (Join-Path $env:LOCALAPPDATA 'OpenZIM\archives')
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
$uvx = (Get-Command uvx.exe -CommandType Application -ErrorAction Stop).Source
$omp = (Get-Command omp.exe -CommandType Application -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $ArchiveDirectory | Out-Null

# Prime uv's cache now. The MCP entry uses --offline to avoid contacting a
# registry during a later offline study session.
& $uvx 'openzim-mcp==3.4.0' --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'OpenZIM MCP installation failed.' }
$agentDir = (& $omp config path | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $agentDir) { throw 'Unable to find OMP configuration directory.' }
$paseoConfig = Join-Path $env:USERPROFILE '.paseo\config.json'
& $uv run --no-project python (Join-Path $PSScriptRoot 'configure_local.py') --agent-dir $agentDir --paseo-config $paseoConfig --uvx $uvx --omp $omp --zim-dir $ArchiveDirectory
if ($LASTEXITCODE -ne 0) { throw 'Could not register OpenZIM MCP and Paseo.' }

$name = 'wikipedia_en_all_nopic_2026-06.zim'
$final = Join-Path $ArchiveDirectory $name
$part = "$final.part"
if (-not (Test-Path -LiteralPath $final -PathType Leaf)) {
    $free = (Get-Item -LiteralPath $ArchiveDirectory).PSDrive.Free
    # Allow a resumed download to count bytes already present.
    $partialSize = if (Test-Path -LiteralPath $part) { (Get-Item -LiteralPath $part).Length } else { 0 }
    if (($free + $partialSize) -lt 55GB) {
        throw "At least 55 GiB free space (including any existing partial download) is needed in $ArchiveDirectory."
    }
    Write-Host 'Downloading full English Wikipedia without pictures (June 2026; approximately 49 GiB).'
    & curl.exe --fail --location --retry 3 --continue-at - --output $part "https://download.kiwix.org/zim/wikipedia/$name"
    if ($LASTEXITCODE -ne 0) { throw 'Wikipedia download failed; rerun this script to resume.' }
    if ((Get-Item -LiteralPath $part).Length -lt 40GB) { throw 'Wikipedia archive is unexpectedly small; refusing to mark complete.' }
    Move-Item -LiteralPath $part -Destination $final
} else {
    Write-Host "Keeping existing archive $final"
}
Write-Host "Registered local OpenZIM MCP; archive: $final. Restart OMP and Paseo."
