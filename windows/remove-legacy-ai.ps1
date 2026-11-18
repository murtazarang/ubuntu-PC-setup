# Pasteable launcher: irm <raw GitHub URL>/remove-legacy-ai.ps1 | iex
& {
    $ErrorActionPreference = 'Stop'
    $folder = Join-Path ([IO.Path]::GetTempPath()) ('pc-setup-legacy-ai-' + [guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $folder | Out-Null
    $file = Join-Path $folder 'Remove-LegacyAI.ps1'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/Remove-LegacyAI.ps1' -OutFile $file
    if ((Get-Content -LiteralPath $file -Raw) -match '^\s*<') { throw 'GitHub returned HTML instead of the cleanup script; nothing executed.' }
    Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/murtazarang/ubuntu-PC-setup/main/windows/cleanup_legacy_config.py' -OutFile (Join-Path $folder 'cleanup_legacy_config.py')
    & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $file -Apply -PurgeQuarantine
    if ($LASTEXITCODE -ne 0) { throw "Cleanup stopped (exit $LASTEXITCODE). Details remain at $folder. Read the error before retrying." }
}
