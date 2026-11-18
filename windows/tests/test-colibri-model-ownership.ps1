# Exercise the installer's actual ownership guard against private fixtures.
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path (Split-Path $PSScriptRoot -Parent) 'Install-Colibri.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$function=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name -eq 'Test-ColibriOwnedMetadata'},$true)
Invoke-Expression $function.Extent.Text
$dir=Join-Path ([IO.Path]::GetTempPath()) ('colibri-owned-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $dir|Out-Null
try{
 $hashes=@{}
 foreach($name in @('gguf.json','config.json','tokenizer.json')){
  '{}'|Set-Content (Join-Path $dir $name)
  $hashes[$name]=(Get-FileHash (Join-Path $dir $name)).Hash
 }
 $conversion=@{hashes=$hashes}|ConvertTo-Json|ConvertFrom-Json
 Test-ColibriOwnedMetadata $conversion $dir
 'user custom configuration'|Set-Content (Join-Path $dir 'config.json')
 $blocked=$false
 try{Test-ColibriOwnedMetadata $conversion $dir}catch{$blocked=$true}
 if(-not $blocked){throw 'Custom metadata was accepted for overwrite'}
 if((Get-Content (Join-Path $dir 'config.json')) -ne 'user custom configuration'){throw 'Guard modified data'}
 $blocked=$false
 try{Test-ColibriOwnedMetadata ([pscustomobject]@{ready=$true}) $dir}catch{$blocked=$true}
 if(-not $blocked){throw 'Missing ownership was accepted'}
 $blocked=$false
 try{Test-ColibriOwnedMetadata ([pscustomobject]@{hashes=[pscustomobject]@{}}) $dir}catch{$blocked=$true}
 if(-not $blocked){throw 'Empty ownership was accepted'}
 '{}'|Set-Content (Join-Path $dir 'config.json')
 $invalidHashes=$hashes.Clone();$invalidHashes['config.json:stream']='bad'
 $blocked=$false
 try{Test-ColibriOwnedMetadata (@{hashes=$invalidHashes}|ConvertTo-Json|ConvertFrom-Json) $dir}catch{$blocked=$_.Exception.Message -like '*Invalid model metadata manifest path*'}
 if(-not $blocked){throw 'Invalid metadata names were accepted'}
 Write-Host 'Actual model ownership guard accepts intact metadata and preserves modified/unowned fixtures.'
}finally{Remove-Item -LiteralPath $dir -Recurse -Force}
