# Exercise the actual Finish shortcut block with an inert COM-shaped object.
$ErrorActionPreference='Stop'
$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Install-OpenWebUI.ps1') -Raw
$begin=$text.IndexOf("`$finish=Join-Path `$desktop 'Finish Open WebUI Setup.lnk'")
if($begin -lt 0){throw 'Finish shortcut block missing'}
$block=[scriptblock]::Create($text.Substring($begin))
$root='C:\fixture\OpenWebUI-PC-Setup';$desktop='C:\fixture\Desktop'
$global:WebUIShortcutFixture=@{}
function global:Test-Path {param($LiteralPath) return $global:WebUIShortcutFixture.Existing}
$shell=New-Object psobject
$shell|Add-Member ScriptMethod CreateShortcut {param($Path) return $global:WebUIShortcutFixture.Link}
try {
    foreach($case in @('fresh','owned-old','custom')){
        $link=[pscustomobject]@{TargetPath='';Arguments='';WorkingDirectory='';Description=''}
        $link|Add-Member ScriptMethod Save {$global:WebUIShortcutFixture.Saves++}
        $global:WebUIShortcutFixture=@{Existing=($case -ne 'fresh');Link=$link;Saves=0}
        if($case -eq 'owned-old'){
            $link.TargetPath=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $link.Arguments='-NoProfile -File "'+(Join-Path $root 'Finish-OpenWebUI.ps1')+'" -Root "'+$root+'"'
            $link.Description='Import complete skills and connect local Wikipedia after account creation.'
        }elseif($case -eq 'custom'){$link.TargetPath='C:\custom\app.exe';$link.Description='custom'}
        & $block
        if($case -eq 'custom'){
            if($global:WebUIShortcutFixture.Saves -ne 0 -or $link.TargetPath -ne 'C:\custom\app.exe'){throw 'Custom shortcut modified'}
        }else{
            if($global:WebUIShortcutFixture.Saves -ne 1 -or $link.Arguments -notlike '*-ExecutionPolicy Bypass*'){throw "$case did not get process-only policy argument"}
        }
    }
    Write-Host 'Finish shortcut tests passed: fresh, repair owned old, preserve custom.'
}finally{Remove-Item Function:\Test-Path -ErrorAction SilentlyContinue;Remove-Variable WebUIShortcutFixture -Scope Global -ErrorAction SilentlyContinue}
