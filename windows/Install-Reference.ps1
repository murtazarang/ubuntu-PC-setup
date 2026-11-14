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

# A dedicated durable tool environment avoids evictable uvx cache and does not
# replace a user's independently installed OpenZIM tool. Restore process settings.
$oldToolDir = $env:UV_TOOL_DIR
$oldToolBinDir = $env:UV_TOOL_BIN_DIR
try {
    $env:UV_TOOL_DIR = Join-Path $env:LOCALAPPDATA 'OpenZIM\tools'
    $env:UV_TOOL_BIN_DIR = Join-Path $env:LOCALAPPDATA 'OpenZIM\bin'
    & $uv tool install --python 3.12 'openzim-mcp==3.4.0'
    if ($LASTEXITCODE -ne 0) { throw 'OpenZIM MCP installation failed.' }
    $bridge = Join-Path $env:UV_TOOL_BIN_DIR 'openzim-mcp.exe'
    if (-not (Test-Path -LiteralPath $bridge -PathType Leaf)) { throw 'OpenZIM executable was not installed.' }
    Write-Host 'Checking OpenZIM MCP startup (--help); this does not download Wikipedia.'
    & $bridge --help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'OpenZIM MCP startup check failed.' }
} finally {
    $env:UV_TOOL_DIR = $oldToolDir
    $env:UV_TOOL_BIN_DIR = $oldToolBinDir
}
Write-Host 'Locating Oh My Pi configuration directory.'
$agentDir = (& $omp config path | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $agentDir) { throw 'Unable to find OMP configuration directory.' }
$paseoHome = if ($env:PASEO_HOME) { $env:PASEO_HOME } else { Join-Path $env:USERPROFILE '.paseo' }
$paseoConfig = Join-Path $paseoHome 'config.json'
$name = 'wikipedia_en_all_nopic_2026-06.zim'
$final = Join-Path $ArchiveDirectory $name
$part = "$final.part"
# Kiwix publishes SHA-256 sidecars. Fetch afresh, never trust a stale checksum.
$checksum = "$final.sha256.download"
Write-Host 'Fetching the official Wikipedia SHA-256 checksum from Kiwix.'
& curl.exe --fail --location --retry 3 --output $checksum "https://download.kiwix.org/zim/wikipedia/$name.sha256"
if ($LASTEXITCODE -ne 0) { throw 'Could not obtain official Wikipedia checksum; archive not registered.' }
$checksumText = (Get-Content -LiteralPath $checksum -Raw).Trim()
if ($checksumText -notmatch '^([0-9a-fA-F]{64})(?:\s+\*?([^\r\n]+))?$') {
    throw 'Unexpected official SHA-256 file format; archive not registered.'
}
$expectedHash = $Matches[1]
if ($Matches.ContainsKey(2) -and $Matches[2] -ne $name) { throw 'Checksum filename does not match requested archive.' }

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
    Write-Host 'Verifying the downloaded Wikipedia archive SHA-256; this may take several minutes without a progress bar.'
    if ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -ne $expectedHash) {
        throw "Wikipedia checksum mismatch. Partial file retained at $part; remove it before retrying a fresh download."
    }
    Move-Item -LiteralPath $part -Destination $final
} else {
    Write-Host 'Verifying the existing Wikipedia archive SHA-256; this may take several minutes without a progress bar.'
    if ((Get-FileHash -LiteralPath $final -Algorithm SHA256).Hash -ne $expectedHash) {
        throw "Existing archive checksum mismatch: $final. File preserved; repair or move it before rerunning."
    }
    Write-Host "Verified existing archive $final"
}
& $uv run --no-project python (Join-Path $PSScriptRoot 'configure_local.py') --agent-dir $agentDir --paseo-config $paseoConfig --bridge $bridge --legacy-uvx $uvx --omp $omp --zim-dir $ArchiveDirectory
if ($LASTEXITCODE -ne 0) { throw 'Could not register OpenZIM MCP and Paseo.' }

Write-Host "Registered local OpenZIM MCP; archive: $final. Restart OMP and Paseo."

