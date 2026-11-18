# Read-only scan of exact deletion candidates, including unregistered/resumable ZIM files.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$CandidatePaths,[string[]]$AllowedLinks=@())
$ErrorActionPreference='Stop'
foreach($path in $CandidatePaths){
    if(-not(Test-Path -LiteralPath $path)){continue}
    $root=Get-Item -LiteralPath $path -Force
    $ancestor=$root
    while($ancestor){
        if($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Linked deletion candidate needs ownership review: $($ancestor.FullName)"}
        $ancestor=if($ancestor -is [IO.DirectoryInfo]){$ancestor.Parent}else{$ancestor.Directory}
    }
    $pending=[Collections.Generic.Stack[System.IO.FileSystemInfo]]::new()
    $pending.Push($root)
    while($pending.Count){
        $item=$pending.Pop()
        if($item.Name -match '(?i)\.zim(?:\.part)?$'){throw "Wikipedia/ZIM archive or resumable download found inside a deletion candidate: $($item.FullName). Nothing at this path was deleted. Move it outside the old stack before cleanup; no automatic relocation is performed."}
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){
            # Only callers that independently validated an exact internal junction may allow it.
            # Its real target must be inside the same scanned tree; never traverse this alias.
            if($AllowedLinks -contains $item.FullName){continue}
            throw "Linked deletion entry needs ownership review: $($item.FullName)"
        }
        if($item -is [IO.DirectoryInfo]){
            foreach($child in @(Get-ChildItem -LiteralPath $item.FullName -Force -ErrorAction Stop)){$pending.Push($child)}
        }
    }
}
