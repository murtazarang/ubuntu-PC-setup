# Read-only migration gate: never remove an active replacement data directory.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$CandidatePaths,[Parameter(Mandatory=$true)][string[]]$ProtectedPaths)
function Normalize([string]$Path){
    if(-not [IO.Path]::IsPathRooted($Path)){throw "Migration path must be absolute: $Path"}
    return [IO.Path]::GetFullPath($Path).Replace('/','\').TrimEnd('\')
}
foreach($protected in $ProtectedPaths){
    $current=[IO.Path]::GetFullPath($protected)
    while($current){
        if(Test-Path -LiteralPath $current){
            if((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Preserved data uses a linked path: $current. Resolve its actual location before legacy deletion."}
        }
        $parent=Split-Path -Path $current -Parent
        if($parent -eq $current){break}
        $current=$parent
    }
}
foreach($candidate in $CandidatePaths){
    $c=Normalize $candidate
    foreach($protected in $ProtectedPaths){
        $p=Normalize $protected
        if($p.Equals($c,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($c+'\',[StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase)){
            throw "Legacy cleanup overlaps preserved data: $candidate and $protected. Nothing was deleted; move the active data and update its configuration before cleanup."
        }
    }
}
