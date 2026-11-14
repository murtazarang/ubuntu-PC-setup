# Safe runtime tests: all Windows Update COM objects are replaced with fixtures.
# No scan, download, installation, registry change or restart is performed.
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-Updates.ps1'

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Reset-Fixture {
    $script:PendingRestart = $false
    $script:InstallRestart = $false
    $script:SessionCalls = 0
    $script:DownloadCalls = 0
    $script:InstallCalls = 0
    $script:OfferedUpdates = @()
    $script:SelectedUpdates = [System.Collections.ArrayList]::new()
}
function New-FixtureUpdate([string]$Title, [int]$Impact = 0) {
    [pscustomobject]@{
        Title = $Title
        EulaAccepted = $true
        InstallationBehavior = [pscustomobject]@{
            Impact = $Impact
            CanRequestUserInput = $false
        }
    }
}
# This locally scoped function intercepts only the COM creation used by the
# production script. Unknown COM objects fail closed instead of reaching Windows.
function New-Object {
    param([string]$ComObject)
    switch ($ComObject) {
        'Microsoft.Update.SystemInfo' {
            return [pscustomobject]@{ RebootRequired = $script:PendingRestart }
        }
        'Microsoft.Update.UpdateColl' { return ,$script:SelectedUpdates }
        'Microsoft.Update.Session' {
            $script:SessionCalls++
            $session = [pscustomobject]@{}
            $session | Add-Member ScriptMethod CreateUpdateSearcher {
                $searcher = [pscustomobject]@{}
                $searcher | Add-Member ScriptMethod Search {
                    param($Criteria)
                    return [pscustomobject]@{ Updates = $script:OfferedUpdates }
                }
                return $searcher
            }
            $session | Add-Member ScriptMethod CreateUpdateDownloader {
                $downloader = [pscustomobject]@{ Updates = $null }
                $downloader | Add-Member ScriptMethod Download {
                    $script:DownloadCalls++
                    return [pscustomobject]@{ ResultCode = 2 }
                }
                return $downloader
            }
            $session | Add-Member ScriptMethod CreateUpdateInstaller {
                $installer = [pscustomobject]@{ Updates = $null }
                $installer | Add-Member ScriptMethod Install {
                    $script:InstallCalls++
                    return [pscustomobject]@{
                        ResultCode = 2
                        RebootRequired = $script:InstallRestart
                    }
                }
                return $installer
            }
            return $session
        }
        default { throw "Unexpected COM request in safe test: $ComObject" }
    }
}

Reset-Fixture
$script:PendingRestart = $true
$caught = $false
try { & $target } catch {
    $caught = $_.Exception.Message -like '*pending update restart*'
}
Assert-True $caught 'Pending restart must stop with actionable guidance.'
Assert-True ($script:SessionCalls -eq 0) 'Pending restart must stop before scanning.'

Reset-Fixture
$script:OfferedUpdates = @((New-FixtureUpdate 'Exclusive' 2))
& $target -WarningVariable warnings 3>$null
Assert-True ($script:SelectedUpdates.Count -eq 0) 'Exclusive update must not enter the batch.'
Assert-True ($script:DownloadCalls -eq 0 -and $script:InstallCalls -eq 0) 'Exclusive-only scan must not download or install.'
Assert-True (($warnings | Out-String) -like '*Exclusive*separate installation*') 'Deferred exclusive update must be named.'

Reset-Fixture
$script:OfferedUpdates = @((New-FixtureUpdate 'Regular'), (New-FixtureUpdate 'Exclusive' 2))
& $target 3>$null
Assert-True ($script:SelectedUpdates.Count -eq 1) 'Mixed batch must retain only the regular update.'
Assert-True ($script:SelectedUpdates[0].Title -eq 'Regular') 'Wrong update selected.'
Assert-True ($script:DownloadCalls -eq 1 -and $script:InstallCalls -eq 1) 'Regular update must be processed once.'

Reset-Fixture
$script:OfferedUpdates = @((New-FixtureUpdate 'Regular'))
$script:InstallRestart = $true
$caught = $false
try { & $target } catch {
    $caught = $_.Exception.Message -like '*require a reboot*'
}
Assert-True $caught 'New restart requirement must stop the enclosing stage.'
Write-Host 'Four mocked Windows Update runtime cases passed; no Windows Update operation ran.'
