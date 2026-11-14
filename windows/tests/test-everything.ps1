# Safe installer-flow tests. All application/service/installer actions are mocked.
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-Everything.ps1'
function Reset-Fixture {
    $script:Running = $false
    $script:ServiceExists = $true
    $script:InstallExit = 0
    $script:Packages = [System.Collections.Generic.List[string]]::new()
    $script:Commands = [System.Collections.Generic.List[string]]::new()
}
function Get-Process { param($Name, $ErrorAction) if ($script:Running) { [pscustomobject]@{ Id = 1 } } }
function winget.exe {
    $index = [Array]::IndexOf($args, '--id')
    if ($index -lt 0 -or $args -notcontains '--no-upgrade') { throw 'Unexpected package arguments.' }
    $script:Packages.Add($args[$index + 1])
    $global:LASTEXITCODE = $script:InstallExit
}
function Get-Command {
    param($Name, $CommandType, $ErrorAction)
    switch ($Name) {
        'uv.exe' { [pscustomobject]@{ Source = 'fake-uv' } }
        'Everything.exe' { [pscustomobject]@{ Source = 'fake-everything.exe' } }
        default { throw "Unmocked command lookup: $Name" }
    }
}
function fake-uv { $global:LASTEXITCODE = 0 }
function Test-Path { param($LiteralPath) return $true }
function Get-Service { param($Name, $ErrorAction) if ($script:ServiceExists) { [pscustomobject]@{ Name = 'Everything' } } }
function Start-Service { param($Name, $ErrorAction) if ($Name -ne 'Everything') { throw 'Unmocked service.' } }
function Start-Process {
    param($FilePath, $ArgumentList, [switch]$Wait, [switch]$PassThru)
    if ($FilePath -ne 'fake-everything.exe') { throw "Unmocked process: $FilePath" }
    $script:Commands.Add([string]$ArgumentList)
    if ($PassThru) { [pscustomobject]@{ ExitCode = 0 } }
}
Reset-Fixture
& $target
if (($script:Packages -join ',') -ne 'voidtools.Everything,lin-ycv.EverythingPowerToys') { throw 'Wrong packages/order.' }
if ($script:Commands -contains '-install-service') { throw 'Reinstalled existing service.' }
if ($script:Commands -notcontains '-startup') { throw 'Everything was not started.' }
Reset-Fixture
$script:ServiceExists = $false
& $target
if ($script:Commands -notcontains '-install-service') { throw 'Missing service was not installed.' }
Reset-Fixture
$script:Running = $true
try { & $target; throw 'Expected running-PowerToys rejection.' } catch {
    if ($_.Exception.Message -notlike 'Exit PowerToys*') { throw }
}
if ($script:Packages.Count -ne 0) { throw 'Installed while PowerToys was running.' }
Reset-Fixture
$script:InstallExit = 5
try { & $target; throw 'Expected package failure.' } catch {
    if ($_.Exception.Message -notlike 'Installing voidtools.Everything failed*') { throw }
}
if ($script:Packages.Count -ne 1 -or $script:Commands.Count -ne 0) { throw 'Continued after package failure.' }
Write-Host 'Four mocked Everything installation cases passed; no installer or service was run.'
