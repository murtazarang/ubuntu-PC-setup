# Safe mocked task registration test; no task or display is started.
$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'autostart.ps1'
$root = Join-Path $env:TEMP ('AX206 startup test ' + [guid]::NewGuid())
$global:AxTask = $null
$global:AxRegistered = 0
$global:AxRemoved = 0
function Get-ScheduledTask { param($TaskPath) if ($global:AxTask) { $global:AxTask } }
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) [pscustomobject]@{Execute=$Execute;Arguments=$Argument;WorkingDirectory=$WorkingDirectory} }
function New-ScheduledTaskTrigger { param([switch]$AtLogOn,$User) if (-not $AtLogOn) { throw 'Not a logon trigger' }; [pscustomobject]@{UserId=$User} }
function New-ScheduledTaskPrincipal { param($UserId,$LogonType,$RunLevel) if ($LogonType -ne 'Interactive' -or $RunLevel -ne 'Highest') { throw 'Wrong principal' }; [pscustomobject]@{UserId=$UserId} }
function New-ScheduledTaskSettingsSet {
 param($ExecutionTimeLimit,$MultipleInstances,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries)
 if ($ExecutionTimeLimit -ne [TimeSpan]::Zero -or $MultipleInstances -ne 'IgnoreNew') { throw 'Wrong lifetime or instance policy' }
 [pscustomobject]@{MultipleInstances=$MultipleInstances}
}
function Register-ScheduledTask {
 param($TaskName,$TaskPath,$Description,$Action,$Trigger,$Principal,$Settings)
 if ($Trigger.UserId -ne $Principal.UserId) { throw 'Trigger/principal identity mismatch' }
 if ($Action.Arguments -ne ('"' + (Join-Path $Action.WorkingDirectory 'autostart_runner.py') + '" --rotation 270')) { throw 'Wrong quoted action arguments' }
 $global:AxRegistered++
 $global:AxTask = [pscustomobject]@{TaskName=$TaskName;Description=$Description;Actions=@($Action);Principal=$Principal;State='Ready'}
}
function Unregister-ScheduledTask { param($TaskName,$TaskPath,$Confirm) $global:AxRemoved++; $global:AxTask=$null }
function Start-ScheduledTask { throw 'Must not start a task' }
function Stop-ScheduledTask { throw 'Must not stop a task' }
function Assert($condition,$message) { if (-not $condition) { throw $message } }
try {
 New-Item -ItemType Directory -Path (Join-Path $root '.venv\Scripts') -Force | Out-Null
 foreach ($file in @('.venv\Scripts\pythonw.exe','panel.py','portrait.yaml')) { Set-Content -LiteralPath (Join-Path $root $file) -Value '' }
 & $source -InstallDir $root
 Assert ($global:AxRegistered -eq 1) 'Registration missing'
 Assert (Test-Path (Join-Path $root 'autostart_runner.py')) 'Runner missing'
 & $source -InstallDir $root
 Assert ($global:AxRegistered -eq 1) 'Rerun duplicated task'
 & $source -InstallDir $root -Action Status | Out-Null
 $failed=$false; try { & $source -InstallDir $root -Rotation 90 } catch { $failed=$true }
 Assert $failed 'Different rotation was silently overwritten'
 # Existing managed task with a nondefault rotation is preserved on ordinary rerun.
 $oldArguments=$global:AxTask.Actions[0].Arguments
 $global:AxTask.Actions[0].Arguments=$oldArguments -replace '270$', '90'
 & $source -InstallDir $root
 Assert ($global:AxRegistered -eq 1 -and $global:AxTask.Actions[0].Arguments.EndsWith('90')) 'Existing rotation not preserved'
 $global:AxTask.Actions[0].Arguments=$oldArguments
 $global:AxTask.Description='Unrelated task'
 $failed=$false; try { & $source -InstallDir $root -Action Remove } catch { $failed=$true }
 Assert ($failed -and $global:AxRemoved -eq 0) 'Unrelated task removed'
 $global:AxTask.Description='ubuntu-PC-setup AX206Panel autostart v1'
 & $source -InstallDir $root -Action Remove
 Assert ($global:AxRemoved -eq 1) 'Removal missing'
 Set-Content -LiteralPath (Join-Path $root 'autostart_runner.py') -Value 'custom'
 $failed=$false; try { & $source -InstallDir $root } catch { $failed=$true }
 Assert $failed 'Custom helper overwritten'
 Assert ((Get-Content (Join-Path $root 'autostart_runner.py') -Raw).Trim() -eq 'custom') 'Custom helper not preserved'
 Write-Host 'PASS: AX206 autostart mock tests'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
