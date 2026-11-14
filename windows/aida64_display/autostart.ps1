#Requires -Version 5.1
# Sign-in task for an already installed AX206Panel. Safe to download with irm | iex.
& {
[CmdletBinding()]
param(
    [ValidateSet('Install','Status','Remove')][string]$Action = 'Install',
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'),
    [ValidateSet(0,90,180,270)][int]$Rotation = 270
)
$ErrorActionPreference = 'Stop'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$sid = $identity.User.Value
$taskName = "AX206Panel-$sid"
$marker = 'ubuntu-PC-setup AX206Panel autostart v1'
$InstallDir = [IO.Path]::GetFullPath($InstallDir).TrimEnd('\')
$python = Join-Path $InstallDir '.venv\Scripts\pythonw.exe'
$runner = Join-Path $InstallDir 'autostart_runner.py'
$arguments = '"' + $runner + '" --rotation ' + $Rotation
$existing = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq $taskName })
if ($existing.Count -gt 0) {
    $task = $existing[0]
    $existingSid = $task.Principal.UserId
    if ($existingSid -notmatch '^S-1-') {
        try { $existingSid = (New-Object Security.Principal.NTAccount($existingSid)).Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { throw "Cannot identify the owner of existing task $taskName. It has not been changed." }
    }
    if ($task.Description -ne $marker -or @($task.Actions).Count -ne 1 -or
        $task.Actions[0].Execute -ne $python -or $existingSid -ne $sid -or
        $task.Actions[0].Arguments -notmatch ('^' + [regex]::Escape('"' + $runner + '" --rotation ') + '(0|90|180|270)$')) {
        throw "A different task named $taskName already exists. It has not been changed. Inspect it in Task Scheduler."
    }
}
if ($Action -eq 'Status') {
    if ($existing.Count) { $existing[0] | Select-Object TaskName,State,Actions }
    else { Write-Host 'AX206 sign-in startup is not enabled.' }
    return
}
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Open PowerShell as administrator under your normal Windows account, then run this command again.'
}
if ($Action -eq 'Remove') {
    if ($existing.Count) { Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false }
    Write-Host 'Sign-in startup removed. No running display process or installed files were changed.'
    return
}
foreach ($file in @($python, (Join-Path $InstallDir 'panel.py'), (Join-Path $InstallDir 'portrait.yaml'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing installed file: $file. Complete the AX206 installation first." }
}
$runnerText = @'
# Managed by ubuntu-PC-setup AX206Panel autostart v1
import os
import runpy
import sys
import traceback
from pathlib import Path

base = Path(__file__).resolve().parent
log = base / "autostart.log"
try:
    if log.exists() and log.stat().st_size > 2_000_000:
        os.replace(log, base / "autostart.previous.log")
    sys.stdout = sys.stderr = log.open("a", encoding="utf-8", buffering=1)
    sys.stdin = open(os.devnull, "r")
    from datetime import datetime
    print("\nAX206 sign-in start:", datetime.now().isoformat())
    os.chdir(base)
    sys.path.insert(0, str(base))
    sys.argv[0] = str(base / "panel.py")
    runpy.run_path(sys.argv[0], run_name="__main__")
except Exception:
    if sys.stderr is not None:
        traceback.print_exc()
    sys.exit(1)
'@
if (Test-Path -LiteralPath $runner) {
    if ((Get-Content -LiteralPath $runner -Raw).Trim() -ne $runnerText.Trim()) {
        throw "Existing $runner differs from this helper. It was preserved; inspect it before enabling startup."
    }
} else {
    # CreateNew prevents overwriting a file created between the existence check and write.
    $stream = [IO.File]::Open($runner, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $bytes = [Text.Encoding]::UTF8.GetBytes($runnerText); $stream.Write($bytes, 0, $bytes.Length) }
    finally { $stream.Dispose() }
}
if ($existing.Count) {
    if ($existing[0].Actions[0].Arguments -ne $arguments) {
        throw 'Startup already exists with a different rotation. Remove it first, then install with the desired rotation. It was not changed.'
    }
    Write-Host 'AX206 sign-in startup is already registered; no task was replaced.'
    return
}
$actionObject = New-ScheduledTaskAction -Execute $python -Argument $arguments -WorkingDirectory $InstallDir
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $sid
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $sid -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Description $marker -Action $actionObject -Trigger $trigger -Principal $taskPrincipal -Settings $settings -ErrorAction Stop | Out-Null
Write-Host 'Enabled: AX206 starts without a terminal the next time this Windows user signs in.'
Write-Host 'The current display was left alone. No password was saved; no drivers were changed.'
Write-Host "Startup errors are recorded in $InstallDir\autostart.log. Do not launch a second foreground copy while the task is running."
} @args
