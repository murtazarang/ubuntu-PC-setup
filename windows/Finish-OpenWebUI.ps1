[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$failed=$false
try {
    & (Join-Path $Root 'venv\Scripts\python.exe') (Join-Path $Root 'openwebui_skills.py') import --root (Join-Path $Root 'skill-repos') --url http://127.0.0.1:8080 --wiki-key-file (Join-Path $Root 'wikipedia-api-key') --reference-manifest (Join-Path $env:LOCALAPPDATA 'OpenZIM\reference.json')
    if($LASTEXITCODE -ne 0){throw 'Import/configuration did not finish. Existing skills and data are retained.'}
    & (Join-Path $Root 'Remove-VerifiedOMP.ps1') -MigrationVerifiedThisRun
    Write-Host 'Open WebUI setup completed. Read the verification summary above.'
} catch { $failed=$true; Write-Error $_ -ErrorAction Continue }
Read-Host 'Press Enter to close'
if($failed){exit 1}
