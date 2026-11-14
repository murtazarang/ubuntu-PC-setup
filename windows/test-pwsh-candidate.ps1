# Real execution of preinstalled PowerShell binaries only; no installation/download.
$ErrorActionPreference = 'Stop'
$source = Get-Content -Raw (Join-Path $PSScriptRoot 'run.ps1')
$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Launcher does not parse.' }
$definition = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Test-PowerShell7Candidate' }, $true)
if (-not $definition) { throw 'Test-PowerShell7Candidate definition missing.' }
Invoke-Expression $definition.Extent.Text
$pwsh = (Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
if (-not (Test-PowerShell7Candidate $pwsh)) { throw "Installed PowerShell 7 candidate rejected: $pwsh" }
$legacy = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $legacy)) { throw 'Required Windows PowerShell fixture is unavailable.' }
if (Test-PowerShell7Candidate $legacy) { throw 'Windows PowerShell 5.1 incorrectly accepted as PowerShell 7.' }
if (Test-PowerShell7Candidate (Join-Path $env:TEMP ([guid]::NewGuid().ToString() + '.exe'))) { throw 'Missing executable accepted.' }
$global:LASTEXITCODE = 0
Write-Host 'Actual preinstalled PowerShell 7 accepted, Windows PowerShell 5.1 and missing binary rejected. No installer ran.'
