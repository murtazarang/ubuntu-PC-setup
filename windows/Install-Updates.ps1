# Install offered, non-hidden Windows software updates using Windows Update Agent.
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$session = New-Object -ComObject Microsoft.Update.Session
$search = $session.CreateUpdateSearcher()
$result = $search.Search("IsInstalled=0 and IsHidden=0 and Type='Software'")
$updates = New-Object -ComObject Microsoft.Update.UpdateColl
$manual = @()
foreach ($update in $result.Updates) {
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
    $result = $installer.Install()
    if ($result.ResultCode -ne 2) { throw "Windows Update installation did not fully succeed (code $($result.ResultCode)). Open Windows Update for details." }
    if ($result.RebootRequired) { throw 'Windows updates require a reboot. Restart and rerun the Drivers stage.' }
} else { Write-Host 'No automatically installable Windows software updates found.' }
if ($manual.Count -gt 0) {
    Write-Warning 'Some updates require user interaction or a license response; finish them in Windows Update:'
    $manual | ForEach-Object { Write-Warning $_ }
}
