# Guard logic only. No service, task, permissions or network changes.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Service.ps1') -FunctionsOnly
$sid='S-1-5-21-1234'
$legacy='C:\Users\Example\AppData\Local\AX206Panel'
$script:FakeTask=[pscustomobject]@{
    TaskName="AX206Panel-$sid"; Description='ubuntu-PC-setup AX206Panel autostart v1'
    Principal=[pscustomobject]@{UserId=$sid}
    Actions=@([pscustomobject]@{Execute="$legacy\.venv\Scripts\pythonw.exe";Arguments='"'+$legacy+'\autostart_runner.py" --rotation 270'})
}
function Get-ScheduledTask {param($TaskPath,$ErrorAction) return $script:FakeTask}
if (-not (Get-OldTask $sid $legacy)) {throw 'Valid migration task not recognized'}
$script:FakeTask.Description='Other task'
$blocked=$false
try {Get-OldTask $sid $legacy} catch {$blocked=$true}
if (-not $blocked) {throw 'Unrelated task accepted'}
$script:FakeTask=$null
if ($null -ne (Get-OldTask $sid $legacy)) {throw 'Missing task not handled'}
$script:FakeService=[pscustomobject]@{Description='ubuntu-PC-setup AX206Panel service v1';PathName='"C:\Program Files\AX206Panel\releases\id\.venv\Scripts\python.exe" -E -s "C:\Program Files\AX206Panel\releases\id\service_host.py"'}
function Get-CimInstance {param($ClassName,$Filter) return $script:FakeService}
if (-not (Get-OwnedService 'C:\Program Files\AX206Panel')) {throw 'Own service not recognized'}
$script:FakeService.PathName='"C:\Users\Example\python.exe"'
$blocked=$false
try {Get-OwnedService 'C:\Program Files\AX206Panel'} catch {$blocked=$true}
if (-not $blocked) {throw 'Unrelated service accepted'}
Write-Host 'PASS: own-task and own-service identity guards'
