# Install offered, non-hidden Windows software updates using Windows Update Agent.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$systemInfo = New-Object -ComObject Microsoft.Update.SystemInfo
if ($systemInfo.RebootRequired) {
    throw 'Windows already has a pending update restart. Restart and rerun the Drivers stage.'
}
$session = New-Object -ComObject Microsoft.Update.Session
$search = $session.CreateUpdateSearcher()
$result = $search.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
if ($result.ResultCode -ne 2) {
    throw "Windows Update search did not fully succeed (code $($result.ResultCode)). Open Windows Update, finish or retry its scan, then rerun the Drivers stage."
}
$updates = New-Object -ComObject Microsoft.Update.UpdateColl
$manual = @()
foreach ($update in $result.Updates) {
    # WUA exclusive updates cannot share a batch with other updates. Leave them
    # to Windows Update rather than silently mixing them into this batch.
    if ($update.InstallationBehavior.Impact -eq 2) {
        $manual += "$($update.Title) (requires a separate installation)"
        continue
    }
    if (-not $update.EulaAccepted -or $update.InstallationBehavior.CanRequestUserInput) {
        $manual += $update.Title
        continue
    }
    [void]$updates.Add($update)
}
if ($updates.Count -gt 0) {
    Write-Host "Downloading $($updates.Count) Windows updates."
    $downloader = $session.CreateUpdateDownloader()
    $downloader.Updates = $updates
    $downloadResult = $downloader.Download()
    if ($downloadResult.ResultCode -ne 2) { throw "Windows Update download did not fully succeed (code $($downloadResult.ResultCode))." }
    $installer = $session.CreateUpdateInstaller()
    $installer.Updates = $updates
    if ($installer.IsBusy) {
        throw 'Another Windows Update installation is in progress. Let it finish, then rerun the Drivers stage.'
    }
    if ($installer.RebootRequiredBeforeInstallation) {
        throw 'Windows Update now requires a restart before installation. Restart and rerun the Drivers stage.'
    }
    $result = $installer.Install()
    if ($result.ResultCode -ne 2) { throw "Windows Update installation did not fully succeed (code $($result.ResultCode)). Open Windows Update for details." }
    if ($result.RebootRequired) { throw 'Windows updates require a reboot. Restart and rerun the Drivers stage.' }
} else { Write-Host 'No automatically installable Windows software updates found.' }
if ($manual.Count -gt 0) {
    Write-Warning 'Some updates require separate installation, user interaction or a license response; finish them in Windows Update:'
    $manual | ForEach-Object { Write-Warning $_ }
}
