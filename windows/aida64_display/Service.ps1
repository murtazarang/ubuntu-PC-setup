#Requires -Version 5.1
# Canonical service installation/migration. No USB or PawnIO driver changes.
[CmdletBinding()]
param(
    [ValidateSet('Install','Status','Remove')][string]$Action = 'Install',
    [string]$LegacyInstallDir = (Join-Path $env:LOCALAPPDATA 'AX206Panel'),
    [ValidateSet(0,90,180,270)][int]$Rotation = 270,
    [switch]$FunctionsOnly
)
$ErrorActionPreference = 'Stop'
$ServiceName = 'AX206Panel'
$ServiceMarker = 'ubuntu-PC-setup AX206Panel service v1'
$OldTaskMarker = 'ubuntu-PC-setup AX206Panel autostart v1'

function Invoke-CheckedNative {
    param([string]$File, [string[]]$Arguments)
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}
function Set-ServiceCommand {
    param([object]$Service,[string]$Command)
    $result = Invoke-CimMethod -InputObject $Service -MethodName Change -Arguments @{PathName=$Command;StartMode='Automatic'}
    if ($result.ReturnValue -ne 0) { throw "Service command update failed with Win32_Service return value $($result.ReturnValue)" }
}
function Assert-NotReparsePoint {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing reparse point: $Path" }
}
function Assert-ProtectedDirectory {
    param([string]$Path)
    Assert-NotReparsePoint $Path
    $acl = Get-Acl -LiteralPath $Path
    $allowed = @('S-1-5-18','S-1-5-32-544') # SYSTEM, Administrators
    $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    if ($owner -notin $allowed) { throw "Service folder owner is not SYSTEM/Administrators: $Path" }
    $writeMask = [Security.AccessControl.FileSystemRights]::Write -bor [Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
        if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writeMask) -and $rule.IdentityReference.Value -notin $allowed) {
            throw "Service folder permits writes by an unprivileged identity: $Path"
        }
    }
}
function New-ProtectedDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) { Assert-ProtectedDirectory $Path; return }
    New-Item -ItemType Directory -Path $Path | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    foreach ($entry in @(@('S-1-5-18','FullControl'),@('S-1-5-32-544','FullControl'),@('S-1-5-32-545','ReadAndExecute'))) {
        $sid = New-Object Security.Principal.SecurityIdentifier($entry[0])
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,$entry[1],'ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
    Assert-ProtectedDirectory $Path
}
function Get-OldTask {
    param([string]$Sid,[string]$LegacyPath)
    $name = "AX206Panel-$Sid"
    $task = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -eq $name })
    if (-not $task.Count) { return $null }
    $task = $task[0]
    $owner = $task.Principal.UserId
    if ($owner -notmatch '^S-1-') { $owner = (New-Object Security.Principal.NTAccount($owner)).Translate([Security.Principal.SecurityIdentifier]).Value }
    $python = Join-Path $LegacyPath '.venv\Scripts\pythonw.exe'
    $runner = Join-Path $LegacyPath 'autostart_runner.py'
    $pattern = '^' + [regex]::Escape('"' + $runner + '" --rotation ') + '(0|90|180|270)$'
    if ($task.Description -ne $OldTaskMarker -or $owner -ne $Sid -or @($task.Actions).Count -ne 1 -or
        $task.Actions[0].Execute -ne $python -or $task.Actions[0].Arguments -notmatch $pattern) {
        throw "Task $name is not the recognized legacy AX206 task. No task was changed."
    }
    return $task
}
function Get-OwnedService {
    param([string]$Root)
    $service = Get-CimInstance Win32_Service -Filter "Name='AX206Panel'"
    if (-not $service) { return $null }
    $prefix = '"' + (Join-Path $Root 'releases\')
    if ($service.Description -ne $ServiceMarker -or -not $service.PathName.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)) {
        throw 'An unrelated AX206Panel service exists. It was not changed.'
    }
    return $service
}
function Read-ServiceConfig {
    param([string]$Root)
    Assert-ProtectedDirectory $Root
    $path = Join-Path $Root 'current.json'
    Assert-ProtectedDirectory $path
    $value = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    $releases = Join-Path $Root 'releases'
    $full = [IO.Path]::GetFullPath([string]$value.release).TrimEnd('\')
    $id = [guid]::Empty
    if ([IO.Path]::GetDirectoryName($full) -ne $releases -or -not [guid]::TryParse([IO.Path]::GetFileName($full),[ref]$id)) { throw 'Service release path is not a canonical managed release.' }
    Assert-ProtectedDirectory $releases
    Assert-ProtectedDirectory $full
    return $value
}
function Invoke-StartupMigration {
$oldTaskXml = $null
$taskWasRunning = $false
$serviceChanged = $false
$serviceStopped = $false
$oldConfigText = if (Test-Path -LiteralPath $oldConfig) { Get-Content -LiteralPath $oldConfig -Raw } else { $null }
try {
    if ($existing) {
        Stop-Service -Name $ServiceName
        $serviceStopped = $true
        Set-ServiceCommand $existing $binPath
    } else {
        New-Service -Name $ServiceName -BinaryPathName $binPath -StartupType Automatic -DisplayName 'AX206 Display Panel' -Description $ServiceMarker | Out-Null
    }
    $serviceChanged = $true
    Invoke-CheckedNative $sc @('description',$ServiceName,$ServiceMarker)
    Invoke-CheckedNative $sc @('failure',$ServiceName,'reset=','86400','actions=','restart/5000/restart/15000/restart/60000')
    Invoke-CheckedNative $sc @('failureflag',$ServiceName,'1')
    # Export before stopping; restore startup on any failed service start.
    if ($task) {
        $oldTaskXml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath '\'
        $taskWasRunning = $task.State -eq 'Running'
        Disable-ScheduledTask -TaskName $task.TaskName -TaskPath '\' | Out-Null
        if ($taskWasRunning) { Stop-ScheduledTask -TaskName $task.TaskName -TaskPath '\' }
    }
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 5
    $status = Get-Service -Name $ServiceName
    if ($status.Status -ne 'Running') { throw "AX206 service exited; see $logs\service.log and Windows Event Viewer." }
    @{release=$release;rotation=$Rotation} | ConvertTo-Json | Set-Content -LiteralPath $oldConfig -Encoding UTF8
    $configAcl = Get-Acl -LiteralPath $oldConfig
    $configAcl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $oldConfig -AclObject $configAcl
    if ($task) { Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath '\' -Confirm:$false }
 } catch {
    $failure = $_
    $rollbackErrors = @()
    if ($serviceChanged -or $serviceStopped) {
        try {
            Stop-Service -Name $ServiceName -ErrorAction Stop
            if ($existing) {
                Set-ServiceCommand (Get-CimInstance Win32_Service -Filter "Name='AX206Panel'") $existing.PathName
                if ($existing.State -eq 'Running') { Start-Service -Name $ServiceName }
            } else { Invoke-CheckedNative $sc @('delete',$ServiceName) }
        } catch { $rollbackErrors += "Service restore: $_" }
    }
    # Independent restoration: service rollback failure must not suppress task restore.
    if ($oldTaskXml) {
        try {
            Register-ScheduledTask -TaskName $task.TaskName -TaskPath '\' -Xml $oldTaskXml -Force | Out-Null
            if ($taskWasRunning) { Start-ScheduledTask -TaskName $task.TaskName -TaskPath '\' }
        } catch { $rollbackErrors += "Task restore: $_" }
    }
    try {
        if ($oldConfigText) { Set-Content -LiteralPath $oldConfig -Value $oldConfigText -Encoding UTF8 }
        elseif (Test-Path -LiteralPath $oldConfig) { Remove-Item -LiteralPath $oldConfig }
    } catch { $rollbackErrors += "Settings restore: $_" }
    foreach ($errorText in $rollbackErrors) { Write-Warning $errorText }
    throw $failure
}
}
if ($FunctionsOnly) { return }
$root = Join-Path $env:ProgramFiles 'AX206Panel'
$logs = Join-Path $env:ProgramData 'AX206Panel'
$sc = Join-Path $env:SystemRoot 'System32\sc.exe'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if ($Action -eq 'Status') {
    Get-OwnedService $root | Select-Object Name,State,StartMode,ExitCode,PathName
    Write-Host "Log: $logs\service.log"
    return
}
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run PowerShell as administrator under your normal Windows account.' }
$existing = Get-OwnedService $root
if ($Action -eq 'Remove') {
    if ($existing) {
        Stop-Service -Name $ServiceName -ErrorAction Stop
        Invoke-CheckedNative $sc @('delete',$ServiceName)
    }
    Write-Host 'AX206 service removed. Runtime, settings, logs and drivers were preserved.'
    return
}
$uv = Get-Command uv.exe -ErrorAction Stop
$LegacyInstallDir = [IO.Path]::GetFullPath($LegacyInstallDir).TrimEnd('\')
$otherTasks = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object { $_.TaskName -like 'AX206Panel-*' -and $_.TaskName -ne "AX206Panel-$($identity.User.Value)" })
if ($otherTasks.Count) { throw "Other-account AX206 startup tasks exist: $($otherTasks.TaskName -join ', '). No task was changed. Resolve these before enabling a machine-wide service." }
$task = Get-OldTask $identity.User.Value $LegacyInstallDir
# Abort if an unrecognized foreground old runner is still using the device.
$legacyProcesses = @(Get-CimInstance Win32_Process | Where-Object {
    $_.Name -in @('python.exe','pythonw.exe') -and $_.CommandLine -and
    $_.CommandLine -match 'AX206Panel' -and
    $_.CommandLine -match '(panel\.py|autostart_runner\.py)'
})
if ($legacyProcesses.Count -and (-not $task -or $task.State -ne 'Running' -or @($legacyProcesses | Where-Object { $_.CommandLine -notmatch 'autostart_runner\.py' }).Count)) {
    throw 'Close the old foreground AX206 panel with Ctrl+C first. No process was killed or task changed.'
}
New-ProtectedDirectory $root
New-ProtectedDirectory $logs
$releases = Join-Path $root 'releases'
New-ProtectedDirectory $releases
$release = Join-Path $releases ([guid]::NewGuid().ToString())
New-ProtectedDirectory $release
$theme = Join-Path $LegacyInstallDir 'portrait.yaml'
$oldConfig = Join-Path $root 'current.json'
$previous = $null
if (Test-Path -LiteralPath $oldConfig) {
    $previous = Read-ServiceConfig $root
    if (-not ([string]$previous.release).StartsWith($releases + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Existing service configuration is inconsistent; preserved for inspection.' }
    Assert-ProtectedDirectory $previous.release
    $theme = Join-Path $previous.release 'portrait.yaml'
    if (-not $PSBoundParameters.ContainsKey('Rotation')) { $Rotation = [int]$previous.rotation }
} elseif ($task -and -not $PSBoundParameters.ContainsKey('Rotation')) {
    $Rotation = [int]([regex]::Match($task.Actions[0].Arguments,'(0|90|180|270)$').Value)
}
if ($Rotation -notin @(0,90,180,270)) { throw 'Invalid saved rotation; no startup was changed.' }
# Stage new trusted runtime before touching the existing service/task.
$commit = '11280756789f1d61b80b49383b255acde62a9c60'
$archive = Join-Path $release 'source.zip'
Invoke-WebRequest "https://github.com/mechcow/win-ax206-display/archive/$commit.zip" -OutFile $archive -UseBasicParsing
Expand-Archive -LiteralPath $archive -DestinationPath $release
Move-Item -LiteralPath (Join-Path $release "win-ax206-display-$commit") -Destination (Join-Path $release 'source')
Remove-Item -LiteralPath $archive
$source = Join-Path $release 'source'
$oldPythonDir = $env:UV_PYTHON_INSTALL_DIR
$oldCacheDir = $env:UV_CACHE_DIR
try {
    $env:UV_PYTHON_INSTALL_DIR = Join-Path $release 'python'
    $env:UV_CACHE_DIR = Join-Path $release 'uv-cache'
    Invoke-CheckedNative $uv.Source @('--no-config','python','install','3.11')
    $basePython = @(& $uv.Source --no-config python find --managed-python 3.11)
    if ($LASTEXITCODE -ne 0 -or $basePython.Count -ne 1 -or -not $basePython[0].StartsWith($release + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Managed Python was not resolved inside protected service runtime.' }
    Invoke-CheckedNative $uv.Source @('--no-config','venv','--copies','--python',$basePython[0],(Join-Path $release '.venv'))
    $python = Join-Path $release '.venv\Scripts\python.exe'
    Invoke-CheckedNative $uv.Source @('--no-config','pip','install','--python',$python,$source,'pywin32')
    Invoke-CheckedNative $python @((Join-Path $source 'tools\fetch_lhm.py'))
} finally {
    $env:UV_PYTHON_INSTALL_DIR = $oldPythonDir
    $env:UV_CACHE_DIR = $oldCacheDir
}
foreach ($name in @('service_host.py','safe_theme.py','panel.py','lifecycle.py','usb_transport.py','Run.ps1','Service.ps1','LICENSE')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $release
}
if (Test-Path -LiteralPath $theme -PathType Leaf) { Copy-Item -LiteralPath $theme -Destination (Join-Path $release 'portrait.yaml') }
else { Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'portrait.yaml') -Destination $release }
@{rotation=$Rotation; log_dir=$logs} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $release 'service.json') -Encoding UTF8
# Read-only validation: imports and render only, no sensor or USB access.
Invoke-CheckedNative $python @('-E','-s','-c','import servicemanager, win32service, win32serviceutil, ax206panel')
Invoke-CheckedNative $python @('-E','-s',(Join-Path $release 'safe_theme.py'),(Join-Path $release 'portrait.yaml'))
Invoke-CheckedNative $python @('-E','-s',(Join-Path $release 'panel.py'),'--preview',(Join-Path $release 'preview.png'))
if (-not (Test-Path -LiteralPath (Join-Path $source 'lib\LibreHardwareMonitorLib.dll'))) { throw 'Sensor library missing; existing startup was not changed.' }
# Make every runtime object administrator-owned; inherited read-only access
# prevents ordinary users from replacing code loaded by LocalSystem.
foreach ($item in @(Get-Item -LiteralPath $release) + @(Get-ChildItem -LiteralPath $release -Recurse -Force)) {
    Assert-NotReparsePoint $item.FullName
    $acl = Get-Acl -LiteralPath $item.FullName
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
    Set-Acl -LiteralPath $item.FullName -AclObject $acl
}
$binPath = '"'  + $python + '" -E -s "' + (Join-Path $release 'service_host.py') + '"'
Invoke-StartupMigration
Write-Host 'AX206 Windows service is running and configured to start at boot, before sign-in.'
Write-Host "Logs: $logs\service.log"
Write-Host 'Recognized legacy scheduled startup was removed; its files and custom theme were preserved.'
Write-Host 'No USB/PawnIO driver was changed. Running service status is not proof of temperature readings or USB output; check the display.'
