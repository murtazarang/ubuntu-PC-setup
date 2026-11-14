# Non-destructive parser check: no installer or setup script is executed.
$ErrorActionPreference = 'Stop'
$failures = @()
Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -File | ForEach-Object {
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count -gt 0) {
        $failures += $errors | ForEach-Object { "$($_.Extent.File):$($_.Extent.StartLineNumber): $($_.Message)" }
    }
}
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Host 'All Windows PowerShell scripts parsed successfully. No installers were executed.'
