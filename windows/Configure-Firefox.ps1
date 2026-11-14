# Must run as an administrator because Firefox's distribution policy is machine-wide.
[CmdletBinding()]
param([switch]$Release)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$uv = (Get-Command uv.exe -CommandType Application -ErrorAction Stop).Source
$firefox = Join-Path $env:ProgramFiles 'Mozilla Firefox\firefox.exe'
if (-not (Test-Path -LiteralPath $firefox)) { throw "Firefox not found at $firefox" }
$policy = Join-Path (Split-Path $firefox) 'distribution\policies.json'
$argsList = @('run','--no-project','python',(Join-Path $PSScriptRoot 'apply_firefox_policy.py'),$policy)
if ($Release) { $argsList += '--release' }
& $uv @argsList
if ($LASTEXITCODE -ne 0) { throw 'Firefox policy merge failed. Check permissions and existing policies.' }
if (-not $Release) {
    Write-Host 'Start Firefox once and allow extensions to initialize, then run this script with -Release to preserve later uBlock filter edits.'
} else { Write-Host 'Released initial uBlock filter settings; other policies remain.' }
