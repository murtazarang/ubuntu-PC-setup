# No network/install execution: check explicit scope isolation and entry points.
$ErrorActionPreference='Stop'
foreach ($name in @('install.ps1','patch.ps1')) {
    $path=Join-Path $PSScriptRoot "..\$name"
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
    if ($errors.Count) {throw "$name parse failed: $errors"}
    $text=Get-Content $path -Raw
    if ($text -notmatch '(?s)& \{.*\} @args') {throw "$name lacks isolated invocation scope"}
}
$patch=Get-Content (Join-Path $PSScriptRoot '..\patch.ps1') -Raw
if ($patch -notmatch 'aida64_display/install\.ps1' -or $patch -match 'New-Service|Register-ScheduledTask|sc\.exe') {throw 'Patch forks installer logic'}
Write-Host 'PASS: launcher parsing, scope shape, canonical patch delegation'
