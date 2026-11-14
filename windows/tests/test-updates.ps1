# Safe runtime tests: all Windows Update COM objects are replaced with fixtures.
# No scan, download, installation, registry change or restart is performed.
$ErrorActionPreference = 'Stop'
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-Updates.ps1'
# One shared reference is resolved through parent scopes. Do not use $script:
# inside mocks: invocation from the production script changes script scope.
$WindowsUpdateTestFixture = @{}

function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw "Assertion failed: $Message" }
}
function Reset-Fixture {
    $WindowsUpdateTestFixture.SearchResultCode = 2
    $WindowsUpdateTestFixture.InstallerBusy = $false
    $WindowsUpdateTestFixture.RestartBeforeInstall = $false
    $WindowsUpdateTestFixture.PendingRestart = $false
    $WindowsUpdateTestFixture.InstallRestart = $false
    $WindowsUpdateTestFixture.SessionCalls = 0
    $WindowsUpdateTestFixture.DownloadCalls = 0
    $WindowsUpdateTestFixture.InstallCalls = 0
    $WindowsUpdateTestFixture.OfferedUpdates = @()
    $WindowsUpdateTestFixture.SelectedUpdates = [System.Collections.ArrayList]::new()
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
            return [pscustomobject]@{ RebootRequired = $WindowsUpdateTestFixture.PendingRestart }
        }
        'Microsoft.Update.UpdateColl' { return ,$WindowsUpdateTestFixture.SelectedUpdates }
        'Microsoft.Update.Session' {
            $WindowsUpdateTestFixture.SessionCalls++
            $session = [pscustomobject]@{}
            $session | Add-Member ScriptMethod CreateUpdateSearcher {
                $searcher = [pscustomobject]@{}
                $searcher | Add-Member ScriptMethod Search {
                    param($Criteria)
                    return [pscustomobject]@{ Updates = $WindowsUpdateTestFixture.OfferedUpdates; ResultCode = $WindowsUpdateTestFixture.SearchResultCode }
                }
                return $searcher
            }
            $session | Add-Member ScriptMethod CreateUpdateDownloader {
                $downloader = [pscustomobject]@{ Updates = $null }
                $downloader | Add-Member ScriptMethod Download {
                    $WindowsUpdateTestFixture.DownloadCalls++
                    return [pscustomobject]@{ ResultCode = 2 }
                }
                return $downloader
            }
            $session | Add-Member ScriptMethod CreateUpdateInstaller {
                $installer = [pscustomobject]@{
                    Updates = $null
                    IsBusy = $WindowsUpdateTestFixture.InstallerBusy
                    RebootRequiredBeforeInstallation = $WindowsUpdateTestFixture.RestartBeforeInstall
                }
                $installer | Add-Member ScriptMethod Install {
                    $WindowsUpdateTestFixture.InstallCalls++
                    return [pscustomobject]@{
                        ResultCode = 2
                        RebootRequired = $WindowsUpdateTestFixture.InstallRestart
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
$WindowsUpdateTestFixture.PendingRestart = $true
$caught = $false
$actualError = '<no error>'
try { & $target } catch {
    $actualError = $_.Exception.Message
    $caught = $actualError -like '*pending update restart*'
}
Assert-True $caught "Pending restart must stop with actionable guidance. Actual: $actualError"
Assert-True ($WindowsUpdateTestFixture.SessionCalls -eq 0) 'Pending restart must stop before scanning.'

Reset-Fixture
$WindowsUpdateTestFixture.OfferedUpdates = @((New-FixtureUpdate 'Exclusive' 2))
& $target -WarningVariable warnings 3>$null
Assert-True ($WindowsUpdateTestFixture.SelectedUpdates.Count -eq 0) 'Exclusive update must not enter the batch.'
Assert-True ($WindowsUpdateTestFixture.DownloadCalls -eq 0 -and $WindowsUpdateTestFixture.InstallCalls -eq 0) 'Exclusive-only scan must not download or install.'
Assert-True (($warnings | Out-String) -like '*Exclusive*separate installation*') 'Deferred exclusive update must be named.'

Reset-Fixture
$WindowsUpdateTestFixture.OfferedUpdates = @((New-FixtureUpdate 'Regular'), (New-FixtureUpdate 'Exclusive' 2))
& $target 3>$null
Assert-True ($WindowsUpdateTestFixture.SelectedUpdates.Count -eq 1) 'Mixed batch must retain only the regular update.'
Assert-True ($WindowsUpdateTestFixture.SelectedUpdates[0].Title -eq 'Regular') 'Wrong update selected.'
Assert-True ($WindowsUpdateTestFixture.DownloadCalls -eq 1 -and $WindowsUpdateTestFixture.InstallCalls -eq 1) 'Regular update must be processed once.'

Reset-Fixture
$WindowsUpdateTestFixture.OfferedUpdates = @((New-FixtureUpdate 'Regular'))
$WindowsUpdateTestFixture.InstallRestart = $true
$caught = $false
$actualError = '<no error>'
try { & $target } catch {
    $actualError = $_.Exception.Message
    $caught = $actualError -like '*require a reboot*'
}
Assert-True $caught "New restart requirement must stop the enclosing stage. Actual: $actualError"
foreach ($searchCode in @(3, 4)) {
    Reset-Fixture
    $WindowsUpdateTestFixture.SearchResultCode = $searchCode
    $WindowsUpdateTestFixture.OfferedUpdates = @((New-FixtureUpdate 'Must not install'))
    $caught = $false
    try { & $target } catch { $caught = $_.Exception.Message -like '*search did not fully succeed*rerun the Drivers stage*' }
    Assert-True $caught 'Partial or failed search must stop with retry guidance.'
    Assert-True ($WindowsUpdateTestFixture.DownloadCalls -eq 0 -and $WindowsUpdateTestFixture.InstallCalls -eq 0) 'Failed search must not download or install.'
}
foreach ($condition in @('InstallerBusy', 'RestartBeforeInstall')) {
    Reset-Fixture
    $WindowsUpdateTestFixture[$condition] = $true
    $WindowsUpdateTestFixture.OfferedUpdates = @((New-FixtureUpdate 'Regular'))
    $caught = $false
    try { & $target } catch {
        $message = $_.Exception.Message
        $caught = if ($condition -eq 'InstallerBusy') {
            $message -like '*installation is in progress*rerun the Drivers stage*'
        } else { $message -like '*restart before installation*rerun the Drivers stage*' }
    }
    Assert-True $caught "Installer precondition $condition must stop with recovery guidance."
    Assert-True ($WindowsUpdateTestFixture.DownloadCalls -eq 1 -and $WindowsUpdateTestFixture.InstallCalls -eq 0) 'New precondition after download must prevent installation.'
}
Write-Host 'Eight mocked Windows Update runtime cases passed; no Windows Update operation ran.' 
