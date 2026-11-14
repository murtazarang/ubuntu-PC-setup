# Execute the reference installer with inert commands and in-memory file fixtures.
# No installer, network request, archive, or user configuration is touched.
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-Reference.ps1'
$ReferenceFixture = @{}
function Assert-Reference($Condition, $Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    switch ($Name) {
        'uv.exe' { [pscustomobject]@{Source='Invoke-ReferenceUv'} }
        'uvx.exe' { [pscustomobject]@{Source='unused-uvx.exe'} }
        'omp.exe' { [pscustomobject]@{Source='Invoke-ReferenceOmp'} }
        default { throw "Unexpected command lookup: $Name" }
    }
}
function Invoke-ReferenceUv {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'tool') {
        $ReferenceFixture.InstallCalls++
        if ($ReferenceFixture.FailInstall) { $global:LASTEXITCODE = 1 }
    } elseif ($args[0] -eq 'run') {
        $ReferenceFixture.RegisterCalls++
        Assert-Reference ($ReferenceFixture.HashCalls -eq 1) 'Registration must follow archive verification.'
    } else { throw 'Unexpected uv call' }
}
function Invoke-ReferenceOmp { $global:LASTEXITCODE = 0; 'C:\fixture\agent' }
function New-Item { param($ItemType, [switch]$Force, $Path) }
function Test-Path {
    param($LiteralPath, $PathType)
    if ($LiteralPath -eq 'Invoke-ReferenceBridge') { return (-not $ReferenceFixture.MissingBridge) }
    if ($LiteralPath -like '*.zim') { return $ReferenceFixture.Existing }
    if ($LiteralPath -like '*.part') { return $ReferenceFixture.Partial }
    throw "Unexpected path: $LiteralPath"
}
function Get-Item {
    param($LiteralPath)
    [pscustomobject]@{Length=49GB; PSDrive=[pscustomobject]@{Free=$ReferenceFixture.Free}}
}
function Get-Content { param($LiteralPath, [switch]$Raw); $ReferenceFixture.Checksum }
function Get-FileHash {
    param($LiteralPath, $Algorithm)
    Assert-Reference ($Algorithm -eq 'SHA256') 'Expected SHA256.'
    $ReferenceFixture.HashCalls++
    [pscustomobject]@{Hash=$ReferenceFixture.ActualHash}
}
function Move-Item { param($LiteralPath, $Destination); $ReferenceFixture.MoveCalls++ }
function curl.exe {
    $global:LASTEXITCODE = 0
    if ($args[-1] -like '*.sha256') { $ReferenceFixture.SidecarCalls++; if ($ReferenceFixture.FailSidecar) { $global:LASTEXITCODE=1 } }
    elseif ($args[-1] -like '*.zim') { $ReferenceFixture.DownloadCalls++; Assert-Reference ($args -contains '--continue-at') 'Download must be resumable.'; if ($ReferenceFixture.FailDownload) { $global:LASTEXITCODE=1 } }
    else { throw 'Unexpected curl URL' }
}
# Redirect only the bridge command path to an inert function. All other path
# construction uses the real Join-Path cmdlet.
function Join-Path {
    param($Path, $ChildPath)
    if ($ChildPath -eq 'openzim-mcp.exe') { return 'Invoke-ReferenceBridge' }
    Microsoft.PowerShell.Management\Join-Path -Path $Path -ChildPath $ChildPath
}
function Invoke-ReferenceBridge { $global:LASTEXITCODE=if ($ReferenceFixture.FailHelp) { 1 } else { 0 } }
$oldLocal = $env:LOCALAPPDATA
$oldUser = $env:USERPROFILE
$oldTool = $env:UV_TOOL_DIR
$oldBin = $env:UV_TOOL_BIN_DIR
try {
    $env:LOCALAPPDATA = 'C:\fixture'
    $env:USERPROFILE = 'C:\fixture\user'
    foreach ($case in @('new-ok', 'existing-ok', 'new-bad', 'existing-bad', 'install-fail', 'invalid-sidecar', 'help-fail', 'missing-bridge', 'sidecar-fail', 'wrong-filename', 'download-fail', 'low-space', 'resume-ok')) {
        $ReferenceFixture.Clear()
        foreach ($key in @('InstallCalls','RegisterCalls','HashCalls','MoveCalls','SidecarCalls','DownloadCalls')) { $ReferenceFixture[$key]=0 }
        $ReferenceFixture.Existing = $case -like 'existing*'
        $ReferenceFixture.FailInstall = $case -eq 'install-fail'
        $ReferenceFixture.FailHelp = $case -eq 'help-fail'
        $ReferenceFixture.MissingBridge = $case -eq 'missing-bridge'
        $ReferenceFixture.FailSidecar = $case -eq 'sidecar-fail'
        $ReferenceFixture.FailDownload = $case -eq 'download-fail'
        $ReferenceFixture.Partial = $case -eq 'resume-ok'
        $ReferenceFixture.Free = if ($case -in @('low-space','resume-ok')) { 10GB } else { 60GB }
        $ReferenceFixture.Checksum = ('a' * 64) + '  wikipedia_en_all_nopic_2026-06.zim'
        $ReferenceFixture.ActualHash = if ($case -like '*bad') { 'b' * 64 } else { 'a' * 64 }
        if ($case -eq 'wrong-filename') { $ReferenceFixture.Checksum=('a' * 64) + '  wrong.zim' }
        if ($case -eq 'invalid-sidecar') { $ReferenceFixture.Checksum='not a checksum' }
        $env:UV_TOOL_DIR='original-tools'
        $env:UV_TOOL_BIN_DIR='original-bin'
        $failure=$null
        try { & $target -ArchiveDirectory 'C:\fixture\archives' } catch { $failure=$_.Exception.Message }
        Assert-Reference ($env:UV_TOOL_DIR -eq 'original-tools' -and $env:UV_TOOL_BIN_DIR -eq 'original-bin') "$case restores tool environment."
        if ($case -like '*-ok') {
            Assert-Reference (-not $failure) "$case should succeed: $failure"
            Assert-Reference ($ReferenceFixture.RegisterCalls -eq 1) "$case registers once."
            Assert-Reference ($ReferenceFixture.MoveCalls -eq [int](-not $ReferenceFixture.Existing)) "$case moves only new files."
        } else {
            Assert-Reference ([bool]$failure) "$case must fail."
            Assert-Reference ($ReferenceFixture.RegisterCalls -eq 0 -and $ReferenceFixture.MoveCalls -eq 0) "$case must not register or publish archive."
            if ($case -like '*bad') { Assert-Reference ($failure -like '*checksum mismatch*') "$case failure: $failure" }
        }
        if ($ReferenceFixture.Existing) { Assert-Reference ($ReferenceFixture.DownloadCalls -eq 0) "$case preserves existing archive." }
    }
    Write-Host 'Reference mock tests passed: checksum success/mismatch, existing archive, malformed checksum, installation failure, registration gating, resume and environment restoration.'
    $global:LASTEXITCODE = 0
} finally {
    $env:LOCALAPPDATA=$oldLocal; $env:USERPROFILE=$oldUser
    $env:UV_TOOL_DIR=$oldTool; $env:UV_TOOL_BIN_DIR=$oldBin
}
