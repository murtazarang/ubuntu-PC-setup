# Safe shortcut construction regression, no COM/engine/model download.
$ErrorActionPreference='Stop'
$path=Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-Colibri.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$function=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'New-ColibriServeShortcut'},$true)
Invoke-Expression $function.Extent.Text
function New-Object {param([string]$ComObject)
 if($ComObject -ne 'WScript.Shell'){throw 'Unexpected object'}
 $shell=[pscustomobject]@{}
 $shell|Add-Member ScriptMethod CreateShortcut {param($path)
   $script:captured=[pscustomobject]@{TargetPath='';Arguments='';WorkingDirectory='';IconLocation='';Description='';Saved=$false}
   $script:captured|Add-Member ScriptMethod Save {$this.Saved=$true}
   return $script:captured
 }
 return $shell
}
$oldRoot=$env:SystemRoot;$env:SystemRoot='C:\Windows'
try{
 foreach($hardware in @('NvidiaSingle','NvidiaDual','Intel')){
  New-ColibriServeShortcut -Python "C:\It's a folder\python.exe" -Coli 'C:\App\coli' -Model "C:\Models\It's a model" -Hardware $hardware -Desktop ([IO.Path]::GetTempPath()) -Icon 'C:\App\serve.ico'
  if(-not $captured.Saved){throw 'Shortcut not saved'}
  $encoded=($captured.Arguments -split ' ')[-1]
  $command=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
  $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($command,[ref]$t,[ref]$e)
  if($e.Count){throw 'Generated native command does not parse'}
  if(-not $command.Contains("C:\Models\It''s a model")){throw 'Model quoting wrong'}
  if(($hardware -eq 'NvidiaDual') -ne $command.Contains("COLI_VK_DEV2='auto'")){throw 'Wrong GPU profile'}
  if($command.Contains("COLI_DENSE_BITS='4'")){throw 'Do not override GGUF quantization'}
  if(-not $command.Contains('serve --host 127.0.0.1 --port 8000') -or -not $command.Contains('ui --host 127.0.0.1 --port 8790') -or $command.Contains(' web ')){throw 'Expected only native serve+ui'}
  if($captured.IconLocation -ne 'C:\App\serve.ico'){throw 'Missing Serve icon'}
 }
 New-ColibriServeShortcut -Python 'C:\App\python.exe' -Coli 'C:\App\coli' -Model 'C:\Models\image' -Hardware NvidiaDual -Desktop ([IO.Path]::GetTempPath()) -Icon 'C:\App\image.ico' -Image
 $command=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($captured.Arguments -split ' ')[-1]))
 $t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseInput($command,[ref]$t,[ref]$e)
 if($e.Count -or -not $command.Contains('web --host 127.0.0.1 --port 8001') -or $command.Contains("COLI_VK_DEV2='auto'")){throw 'Invalid image shortcut command'}
 # Execute the actual generated text command with process/UI test doubles.
 function Start-Process {param($FilePath,$ArgumentList,[switch]$PassThru)
  $script:spawn=@{File=$FilePath;Arguments=$ArgumentList}
  return [pscustomobject]@{Id=-1}
 }
 function Invoke-ColibriTestUi {$script:uiArgs=@($args);$global:LASTEXITCODE=0}
 New-ColibriServeShortcut -Python Invoke-ColibriTestUi -Coli 'C:\App\coli' -Model 'C:\Models\text' -Hardware NvidiaDual -Desktop ([IO.Path]::GetTempPath()) -Icon 'C:\App\serve.ico'
 $command=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($captured.Arguments -split ' ')[-1]))
 # Occupied backend must prevent any attempted process start.
 $occupied=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,8000)
 $occupied.Start();$script:spawn=$null;$blocked=$false
 try{Invoke-Expression $command}catch{$blocked=$true}finally{$occupied.Stop()}
 if(-not $blocked -or $script:spawn){throw 'Occupied port was not preserved'}
 Invoke-Expression $command
 if($spawn.File -ne 'Invoke-ColibriTestUi' -or -not $spawn.Arguments.Contains('serve --host 127.0.0.1 --port 8000')){throw 'Wrong native backend invocation'}
 if(($uiArgs -join ' ') -notlike '*ui --host 127.0.0.1 --port 8790 --backend http://127.0.0.1:8000*'){throw 'Wrong native modern UI invocation'}
 Write-Host 'Serve shortcut arguments parse for all three hardware profiles; no inference executed.'
}finally{$env:SystemRoot=$oldRoot}
