# Execute the actual migration transaction with service/task/ACL test doubles.
# The only writes are temporary JSON files. No service or task is changed.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Service.ps1') -FunctionsOnly
$root=Join-Path ([IO.Path]::GetTempPath()) ('ax-migrate-'+[guid]::NewGuid())
New-Item -ItemType Directory $root | Out-Null
$oldConfig=Join-Path $root 'current.json'
$release='C:\Program Files\AX206Panel\releases\new'
$Rotation=90
$binPath='"C:\Program Files\AX206Panel\releases\new\python.exe"'
$sc='sc.exe'
$logs='C:\ProgramData\AX206Panel'
$script:Events=[Collections.Generic.List[string]]::new()
$script:Fail=''
function Stop-Service {param($Name,$ErrorAction) $script:Events.Add('stop-service'); if($script:Fail -eq 'rollback'){throw 'rollback-stop-fail'}}
function Set-ServiceCommand {param($Service,$Command) $script:Events.Add('set:'+ $Command); if($script:Fail -eq 'config' -and $Command -eq $binPath){throw 'config-fail'}}
function New-Service {param($Name,$BinaryPathName,$StartupType,$DisplayName,$Description) $script:Events.Add('create')}
function Invoke-CheckedNative {param($File,$Arguments) $script:Events.Add(($Arguments -join '|'))}
function Export-ScheduledTask {param($TaskName,$TaskPath) return '<saved/>'}
function Disable-ScheduledTask {param($TaskName,$TaskPath) $script:Events.Add('disable-task')}
function Stop-ScheduledTask {param($TaskName,$TaskPath) $script:Events.Add('stop-task')}
function Start-Service {param($Name) $script:Events.Add('start-service'); if($script:Fail -in @('start','rollback')){throw 'start-fail'}}
function Start-Sleep {param($Seconds)}
function Get-Service {param($Name) return [pscustomobject]@{Status='Running'}}
function Get-CimInstance {param($ClassName,$Filter) return $existing}
function Unregister-ScheduledTask {param($TaskName,$TaskPath,$Confirm) $script:Events.Add('remove-task')}
function Register-ScheduledTask {param($TaskName,$TaskPath,$Xml,[switch]$Force) $script:Events.Add('restore-task')}
function Start-ScheduledTask {param($TaskName,$TaskPath) $script:Events.Add('start-task')}
function Get-Acl {param($LiteralPath) $o=New-Object PSObject; $o | Add-Member ScriptMethod SetOwner {param($owner)}; return $o}
function Set-Acl {param($LiteralPath,$AclObject)}
function Assert($condition,$message) {if(-not $condition){throw $message}}
try {
    $task=[pscustomobject]@{TaskName='AX206Panel-test';State='Running'}
    $existing=$null
    Invoke-StartupMigration
    Assert ($script:Events.Contains('remove-task')) 'Success did not remove old startup'
    Assert ($script:Events.IndexOf('start-service') -lt $script:Events.IndexOf('remove-task')) 'Task removed before service start'
    Assert ((Get-Content $oldConfig -Raw | ConvertFrom-Json).rotation -eq 90) 'Rotation not persisted'
    $script:Events.Clear();$script:Fail='start'
    Remove-Item $oldConfig
    $failed=$false
    try {Invoke-StartupMigration} catch {$failed=$true}
    Assert $failed 'Failed service startup was swallowed'
    Assert ($script:Events.Contains('restore-task') -and $script:Events.Contains('start-task')) 'Old task not restored'
    Assert (-not (Test-Path $oldConfig)) 'Failed setup retained new config'
    Assert (-not $script:Events.Contains('remove-task')) 'Failed setup unregistered old task'
    $script:Events.Clear();$script:Fail='rollback'
    try {Invoke-StartupMigration} catch {}
    Assert ($script:Events.Contains('restore-task')) 'Service rollback error suppressed task restoration'
    $script:Events.Clear();$script:Fail='config'
    $existing=[pscustomobject]@{PathName='old-command';State='Running'}
    Set-Content $oldConfig '{"release":"old","rotation":270}'
    $failed=$false
    try {Invoke-StartupMigration} catch {$failed=$true}
    Assert $failed 'Config failure was swallowed'
    Assert ($script:Events.Contains('set:old-command') -and $script:Events.Contains('start-service')) 'Stopped old service was not restarted after config failure'
    Assert (-not $script:Events.Contains('disable-task')) 'Task touched before service config succeeded'
    Assert ((Get-Content $oldConfig -Raw | ConvertFrom-Json).rotation -eq 270) 'Original config not retained'
    Write-Host 'PASS: migration success ordering, failed start restores task/config, failed config restarts old service'
} finally {Remove-Item $root -Recurse -Force}
