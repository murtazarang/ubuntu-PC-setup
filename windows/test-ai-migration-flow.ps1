# Executes the real orchestration block with inert helper files and real Python fixtures.
$ErrorActionPreference='Stop'
$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Migrate-AI.ps1') -Raw
$start=$text.IndexOf('# BEGIN migration stages');$end=$text.IndexOf('# END migration stages')
if($start -lt 0 -or $end -le $start){throw 'Migration stage markers missing'}
$block=$text.Substring($start,$end-$start)
foreach($forbidden in @('Setup.ps1','Install-Apps.ps1','Configure-Firefox.ps1','Install-Drivers.ps1','Configure-Desktop.ps1')){
    if($block.Contains($forbidden)){throw "Unrelated stage in AI migration: $forbidden"}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ai-migration-flow-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
$old=@{};foreach($key in @('TEST_AI_ROOT','TEST_AI_LOG','TEST_FAIL_IMPORT','TEST_FAIL_LEGACY','TEST_LEGACY_ROOT','LOCALAPPDATA')){$old[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
try {
    $root=Join-Path $temp 'root';$env:TEST_AI_ROOT=$root
    $env:LOCALAPPDATA=$temp
    New-Item -ItemType Directory -Path (Join-Path $temp 'Colibri-PC-Setup')|Out-Null
    Set-Content (Join-Path $temp 'Colibri-PC-Setup\settings.json') '{"models":"C:\\fixture-models"}'
    Set-Content (Join-Path $temp 'reference.json') '{"archive":"C:\\fixture-archives\\wiki.zim","archive_directory":"C:\\fixture-archives"}'
    Copy-Item (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') $temp
    & python -m venv (Join-Path $root 'venv')
    if($LASTEXITCODE -ne 0){throw 'Fixture Python creation failed'}
    Set-Content (Join-Path $root 'desktop.json') '{"text_model":"C:\\fixture-models\\text","image_model":"C:\\fixture-models\\image"}'
    Set-Content (Join-Path $root 'openwebui_desktop.py') "import os,sys; open(os.environ['TEST_AI_LOG'],'a').write(sys.argv[1]+'\n')"
    Set-Content (Join-Path $root 'openwebui_skills.py') "import os,sys; assert '--reference-manifest' in sys.argv; open(os.environ['TEST_AI_LOG'],'a').write('verified-import\n'); sys.exit(1 if os.environ.get('TEST_FAIL_IMPORT')=='1' else 0)"
    foreach($name in @('Install-Reference.ps1','Install-Colibri.ps1','Install-OpenWebUI.ps1')){
        Set-Content (Join-Path $temp $name) "Add-Content -LiteralPath `$env:TEST_AI_LOG -Value '$name'"
    }
    Set-Content (Join-Path $temp 'Remove-LegacyAI.ps1') 'param([switch]$Apply,[switch]$RequireRemoval,[switch]$SkipOmpConfig); if($MyInvocation.InvocationName -eq "."){function Get-LegacyCandidates {if($env:TEST_LEGACY_ROOT){return [pscustomobject]@{Path=$env:TEST_LEGACY_ROOT}};return @()};return}; if(-not($Apply -and $RequireRemoval -and $SkipOmpConfig)){throw "Missing migration guards"}; Add-Content $env:TEST_AI_LOG legacy; if($env:TEST_FAIL_LEGACY -eq "1"){throw "Declined fixture"}'
    Set-Content (Join-Path $temp 'Remove-VerifiedOMP.ps1') 'param([switch]$MigrationVerifiedThisRun);if(-not $MigrationVerifiedThisRun){throw "Missing verification gate"};Add-Content $env:TEST_AI_LOG omp'
    Set-Content (Join-Path $temp 'Remove-OMPBinary.ps1') '# inert fixture'
    $driver=Join-Path $temp 'driver.ps1'
    Set-Content $driver ('$ErrorActionPreference="Stop";$root=$env:TEST_AI_ROOT;$Hardware="NvidiaSingle";$ArchiveDirectory="C:\fixture";$reference=Join-Path $env:LOCALAPPDATA "reference.json"'+[Environment]::NewLine+$block)
    foreach($case in @('import-fails','legacy-declines','success','linked-weights')){
        $env:TEST_AI_LOG=Join-Path $temp ($case+'.log')
        $env:TEST_LEGACY_ROOT=''
        if($case -eq 'linked-weights'){
            $env:TEST_LEGACY_ROOT='C:\fixture-legacy'
            $activeModel=Join-Path $root 'custom-model'
            New-Item -ItemType Directory -Path $activeModel -Force|Out-Null
            @{format='colibri-gguf-v1';gguf='C:\fixture-legacy\weights\model.gguf'}|ConvertTo-Json|Set-Content (Join-Path $activeModel 'gguf.json')
            @{text_model=$activeModel;image_model='C:\fixture-models\image'}|ConvertTo-Json|Set-Content (Join-Path $root 'desktop.json')
        }

        $env:TEST_FAIL_IMPORT=if($case -eq 'import-fails'){'1'}else{'0'}
        $env:TEST_FAIL_LEGACY=if($case -eq 'legacy-declines'){'1'}else{'0'}
        '' | & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $driver 2>$null
        $code=$LASTEXITCODE;$events=@(Get-Content $env:TEST_AI_LOG)
        if('text' -in $events -or 'image' -in $events){throw 'Migration must not start or switch a model'}
        if($case -eq 'success'){
            if($code -ne 0 -or $events[-2] -ne 'legacy' -or $events[-1] -ne 'omp'){throw 'Successful migration ordering failed'}
        }elseif($code -eq 0 -or 'omp' -in $events){throw "$case did not block OMP removal"}
        if($case -in @('import-fails','linked-weights') -and 'legacy' -in $events){throw 'Unverified import reached legacy cleanup'}
    }
    & (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') -CandidatePaths @('C:\legacy') -ProtectedPaths @('C:\wiki')
    $blocked=$false
    try {& (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') -CandidatePaths @('C:\legacy') -ProtectedPaths @('C:\legacy\wiki.zim')}catch{$blocked=$true}
    if(-not $blocked){throw 'Active corpus overlap was not blocked'}
    Write-Host 'AI-only migration stages passed: verification gate, decline gate, legacy-before-OMP and no unrelated stage.'
}finally{
    foreach($key in $old.Keys){[Environment]::SetEnvironmentVariable($key,$old[$key],'Process')}
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
