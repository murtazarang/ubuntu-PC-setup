# Install the complete skill collections into Oh My Pi for the current Windows user.
# Requires Git for Windows, uv and Oh My Pi already available on PATH.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Join-Path $env:LOCALAPPDATA 'OMP-Skills'
New-Item -ItemType Directory -Force -Path $root | Out-Null

function Get-CheckedOutRepo([string]$Url, [string]$Destination) {
    if (Test-Path (Join-Path $Destination '.git')) {
        Write-Host "Keeping existing repository $Destination"
    } elseif (Test-Path $Destination) {
        throw "Not overwriting existing path $Destination"
    } else {
        & git clone --depth 1 $Url $Destination
        if ($LASTEXITCODE -ne 0) { throw "Git clone failed: $Url" }
    }
}
$science = Join-Path $root 'scientific-agent-skills'
$writer = Join-Path $root 'claude-scientific-writer'
Get-CheckedOutRepo 'https://github.com/K-Dense-AI/scientific-agent-skills.git' $science
Get-CheckedOutRepo 'https://github.com/K-Dense-AI/claude-scientific-writer.git' $writer

$education = Join-Path $root 'education-agent-skills'
if (-not (Test-Path $education)) {
    $temp = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $temp | Out-Null
    try {
        $archive = Join-Path $temp 'education.zip'
        Invoke-WebRequest -Uri 'https://github.com/GarethManning/education-agent-skills/releases/download/v3.1.0/education-agent-skills-portable-v3.1.0.zip' -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $temp 'extract')
        $export = Join-Path $temp 'extract'
        if (-not (Test-Path (Join-Path $export 'agent-skills'))) {
            throw 'Education archive layout differs from the documented portable edition.'
        }
        Move-Item -LiteralPath $export -Destination $education
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$roots = @((Join-Path $science 'skills'), (Join-Path $writer 'skills'),
           (Join-Path $education 'agent-skills'))
foreach ($path in $roots) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) { throw "Missing skills directory $path" }
}
$state = (& omp config get skills.customDirectories --json | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Could not read Oh My Pi skills configuration' }
$existing = @($state.value)
$combined = @($existing + $roots | Select-Object -Unique)
# PowerShell's native argument marshalling differs by version. Passing compact JSON as one argument
# is required by omp; verify the final value below.
$json = ConvertTo-Json -InputObject $combined -Compress
& omp config set skills.customDirectories $json
if ($LASTEXITCODE -ne 0) { throw 'Could not register skill directories' }
& omp config set skills.enabled true
if ($LASTEXITCODE -ne 0) { throw 'Could not enable skills' }
& omp config set skills.enableSkillCommands true
if ($LASTEXITCODE -ne 0) { throw 'Could not enable skill commands' }
$listed = (& omp skill list --json | Out-String | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Oh My Pi skill inventory' }
$loaded = @{}
foreach ($item in $listed.skills) {
    $loaded[[IO.Path]::GetFullPath($item.filePath).ToLowerInvariant()] = $true
}
$missing = @()
foreach ($rootDir in $roots) {
    Get-ChildItem -LiteralPath $rootDir -Directory | ForEach-Object {
        $file = Join-Path $_.FullName 'SKILL.md'
        if ((Test-Path $file) -and -not $loaded.ContainsKey([IO.Path]::GetFullPath($file).ToLowerInvariant())) {
            $missing += $file
        }
    }
}
if ($missing.Count -gt 0) {
    $missing | ForEach-Object { Write-Error "Skill not discovered: $_" -ErrorAction Continue }
    throw "Oh My Pi missed $($missing.Count) skill definitions"
}
$agentDir = (& omp config path | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $agentDir) { throw 'Unable to locate Oh My Pi agent directory.' }
New-Item -ItemType Directory -Force -Path $agentDir | Out-Null
$rules = Join-Path $agentDir 'RULES.md'
$tag = '<!-- ubuntu-pc-setup-local-ai -->'
$prior = if (Test-Path -LiteralPath $rules) { [string](Get-Content -LiteralPath $rules -Raw) } else { '' }
if (-not $prior.Contains($tag)) {
    $block = @'

<!-- ubuntu-pc-setup-local-ai -->
Use the configured local model by default. Imported skills may describe hosted AI services; do not require their accounts or use them unless the user chooses to do so. Prefer locally available tools, and say when an operation needs an unavailable external service. Other model providers remain available when the user chooses them.
For factual educational questions, consult the user's relevant course materials first when available. Search and read relevant local reference passages before citing them, identify the article and source, and note that offline snapshots may be dated. Do not invent citations.
<!-- /ubuntu-pc-setup-local-ai -->
'@
    Add-Content -LiteralPath $rules -Value $block -Encoding UTF8
}
Write-Host 'All discovered skill definitions are registered; restart Oh My Pi.'
