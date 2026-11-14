# App Paths (Default) is the fully qualified executable path, not its Path value.
# https://learn.microsoft.com/en-us/windows/win32/shell/app-registration
function Find-DesktopExecutable {
    param([string]$Name, [string[]]$Fallbacks, [string]$ExplicitPath = '')
    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf) -or
            [IO.Path]::GetFileName($ExplicitPath) -ine $Name) {
            throw "Expected an existing $Name executable, got: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }
    $candidates = @()
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-Path -LiteralPath $command.Source -PathType Leaf)) { return $command.Source }
    foreach ($base in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths',
                        'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths',
                        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths')) {
        $key = Join-Path $base $Name
        if (Test-Path -LiteralPath $key) { $candidates += (Get-Item -LiteralPath $key).GetValue('') }
    }
    $candidates += $Fallbacks
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    }
    throw "$Name not found in PATH, App Paths, or standard locations. Rerun this component with its explicit executable-path parameter for a custom installation."
}
