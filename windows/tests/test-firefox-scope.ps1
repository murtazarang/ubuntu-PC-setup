# Test the guard extracted from production; no browser/policy/installer executes.
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path (Split-Path $PSScriptRoot -Parent) 'Configure-Firefox.ps1')
$start = $source.IndexOf('if (-not $Release) {')
$end = $source.IndexOf('$uv =', $start)
if ($start -lt 0 -or $end -lt 0) { throw 'Firefox scope guard not found.' }
$guard = [scriptblock]::Create($source.Substring($start, $end - $start))
$FirefoxScopeFixture = @{ Profiles = @(); Fail = $false }
function Get-CimInstance {
    param($ClassName, $ErrorAction)
    if ($ClassName -ne 'Win32_UserProfile') { throw 'Unexpected query.' }
    if ($FirefoxScopeFixture.Fail) { throw 'Profile query unavailable' }
    $FirefoxScopeFixture.Profiles
}
$Release = $false
$FirefoxScopeFixture.Profiles = @(
    [pscustomobject]@{ SID = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value; Special = $false },
    [pscustomobject]@{ SID = 'S-1-5-18'; Special = $true }
)
& $guard
$FirefoxScopeFixture.Profiles += [pscustomobject]@{ SID = 'S-1-5-21-other'; Special = $false }
try { & $guard; throw 'Expected multi-user rejection' }
catch { if ($_.Exception.Message -notlike 'Other Windows user profiles exist*') { throw } }
$Release = $true
& $guard
$Release = $false
$FirefoxScopeFixture.Fail = $true
try { & $guard; throw 'Expected inventory rejection' }
catch { if ($_.Exception.Message -ne 'Profile query unavailable') { throw } }
Write-Host 'Four Firefox scope guard cases passed; no browser policies changed.'
$global:LASTEXITCODE = 0
