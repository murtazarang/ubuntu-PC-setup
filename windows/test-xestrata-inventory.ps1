# Safe function-only tests. No executables, setup, models, or settings touched.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$target = Join-Path $PSScriptRoot 'Install-Model.ps1'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($target,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$f=$ast.Find({param($a) $a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Test-XeStrataNeedsPreparation'},$true)
Invoke-Expression $f.Extent.Text
$script:Raw=''; $script:Exit=0
function Invoke-XeFixture {
    if ($args.Count -ne 1 -or $args[0] -ne '--describe') { throw 'Unexpected command: installer must not run in this test.' }
    $global:LASTEXITCODE=$script:Exit
    $script:Raw
}
function Assert-Throws {
    $failed=$false
    try { $null=Test-XeStrataNeedsPreparation -Executable Invoke-XeFixture } catch { $failed=$true }
    if (-not $failed) { throw 'Expected fail-closed inventory rejection.' }
}
$script:Raw='{"installed":[]}'
if (-not (Test-XeStrataNeedsPreparation -Executable Invoke-XeFixture)) { throw 'Fresh setup should prepare.' }
$one='{"family":"gyro","model":null,"model_name":"qwen3.8-flash-next-gyro-gyro-s","context":32768,"config":"C:\\models\\xestrata-gyro-gyro-s.json"}'
$script:Raw='{"installed":['+$one+']}'
if (Test-XeStrataNeedsPreparation -Executable Invoke-XeFixture) { throw 'Existing correct model must skip preparation.' }
foreach ($raw in @('garbage','{}','{"installed":null}','{"installed":{}}','{"installed":[{}]}', ('{"installed":['+$one+','+$one+']}'), ('{"installed":['+$one.Replace('32768','65536')+']}'), ('{"installed":['+$one.Replace('gyro-gyro-s','gyro-gyro-m')+']}'))) {
    $script:Raw=$raw; Assert-Throws
}
$script:Raw='{"installed":[]}'; $script:Exit=1; Assert-Throws
Write-Host 'XeStrata model inventory tests passed.'
