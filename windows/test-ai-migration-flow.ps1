# Executes the real orchestration block with inert helper files and real Python fixtures.
$ErrorActionPreference='Stop'
$text=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Migrate-ExistingAI.ps1') -Raw
$start=$text.IndexOf('# BEGIN migration stages');$end=$text.IndexOf('# END migration stages')
if($start -lt 0 -or $end -le $start){throw 'Migration stage markers missing'}
$block=$text.Substring($start,$end-$start)
foreach($forbidden in @('Setup.ps1','Install-Apps.ps1','Configure-Firefox.ps1','Install-Drivers.ps1','Configure-Desktop.ps1')){
    if($block.Contains($forbidden)){throw "Unrelated stage in AI migration: $forbidden"}
}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('ai-migration-flow-'+[guid]::NewGuid())
New-Item -ItemType Directory -Path $temp|Out-Null
$old=@{};foreach($key in @('TEST_AI_ROOT','TEST_AI_LOG','TEST_FAIL_INSTALL','TEST_FAIL_LEGACY','TEST_LEGACY_ROOT','LOCALAPPDATA')){$old[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
try {
    $root=Join-Path $temp 'root';$env:TEST_AI_ROOT=$root
    $env:LOCALAPPDATA=$temp
    New-Item -ItemType Directory -Path (Join-Path $temp 'Colibri-PC-Setup')|Out-Null
    Set-Content (Join-Path $temp 'Colibri-PC-Setup\settings.json') '{"models":"C:\\fixture-models"}'
    Set-Content (Join-Path $temp 'reference.json') '{"archive":"C:\\fixture-archives\\wiki.zim","archive_directory":"C:\\fixture-archives"}'
    Copy-Item (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') $temp
    Copy-Item (Join-Path $PSScriptRoot 'Assert-NoCorpus.ps1') $temp
    & python -m venv (Join-Path $root 'venv')
    if($LASTEXITCODE -ne 0){throw 'Fixture Python creation failed'}
    Set-Content (Join-Path $root 'desktop.json') '{"text_model":"C:\\fixture-models\\text","image_model":"C:\\fixture-models\\image"}'
    Set-Content (Join-Path $root 'openwebui_desktop.py') "import os,sys; open(os.environ['TEST_AI_LOG'],'a').write(sys.argv[1]+'\n')"
    Set-Content (Join-Path $temp 'Install-HermesLocalAI.ps1') 'param([string]$Hardware,[string]$ArchiveDirectory);if($Hardware -ne "NvidiaSingle" -or $ArchiveDirectory -ne "C:\fixture"){throw "Lost installation arguments"};Add-Content $env:TEST_AI_LOG install;if($env:TEST_FAIL_INSTALL -eq "1"){throw "Installer failed fixture"}'
    Set-Content (Join-Path $temp 'Retire-LegacyText.ps1') 'param([string]$Root);if($Root -ne $env:TEST_AI_ROOT){throw "Wrong old root"};Add-Content $env:TEST_AI_LOG retire'
    Set-Content (Join-Path $temp 'Remove-LegacyAI.ps1') 'param([switch]$Apply,[switch]$RequireRemoval,[switch]$SkipOmpConfig); if($MyInvocation.InvocationName -eq "."){function Assert-LegacyCorpusAbsent($Candidates) {& (Join-Path $PSScriptRoot "Assert-NoCorpus.ps1") -CandidatePaths @($Candidates|ForEach-Object {$_.Path})}; function Get-LegacyCandidates {if($env:TEST_LEGACY_ROOT){return [pscustomobject]@{Path=$env:TEST_LEGACY_ROOT}};return @()};return}; if(-not($Apply -and $RequireRemoval -and $SkipOmpConfig)){throw "Missing migration guards"}; Add-Content $env:TEST_AI_LOG legacy; if($env:TEST_FAIL_LEGACY -eq "1"){throw "Declined fixture"}'
    Set-Content (Join-Path $temp 'Remove-VerifiedOMP.ps1') 'param([switch]$CleanupAuthorizedThisRun,[switch]$InventoryOnly);if(-not $CleanupAuthorizedThisRun){throw "Missing authorization gate"};if($InventoryOnly){Add-Content $env:TEST_AI_LOG omp-inventory}else{Add-Content $env:TEST_AI_LOG omp}'
    Set-Content (Join-Path $temp 'Remove-OMPBinary.ps1') '# inert fixture'
    Set-Content (Join-Path $temp 'Remove-OldSkillCollections.ps1') 'param([switch]$CleanupAuthorizedThisRun,[string[]]$ProtectedPaths,[switch]$InventoryOnly);if(-not $CleanupAuthorizedThisRun){throw "Missing gate"};if($InventoryOnly){Add-Content $env:TEST_AI_LOG old-inventory}else{Add-Content $env:TEST_AI_LOG old-skills}'
    $driver=Join-Path $temp 'driver.ps1'
    Set-Content $driver ('$ErrorActionPreference="Stop";$root=$env:TEST_AI_ROOT;$Hardware="NvidiaSingle";$ArchiveDirectory="C:\fixture";$reference=Join-Path $env:LOCALAPPDATA "reference.json"'+[Environment]::NewLine+$block)
    foreach($case in @('install-fails','legacy-declines','success','linked-weights','unregistered-zim','unregistered-part')){
        $env:TEST_AI_LOG=Join-Path $temp ($case+'.log')
        # A correct protection preflight can reject the run before any stage emits an event.
        [IO.File]::WriteAllText($env:TEST_AI_LOG,'')
        $env:TEST_LEGACY_ROOT=''
        Set-Content (Join-Path $root 'desktop.json') '{"text_model":"C:\\fixture-models\\text","image_model":"C:\\fixture-models\\image"}'
        if($case -eq 'linked-weights'){
            $env:TEST_LEGACY_ROOT='C:\fixture-legacy'
            $activeModel=Join-Path $root 'custom-model'
            New-Item -ItemType Directory -Path $activeModel -Force|Out-Null
            @{format='colibri-gguf-v1';gguf='C:\fixture-legacy\weights\model.gguf'}|ConvertTo-Json|Set-Content (Join-Path $activeModel 'gguf.json')
            @{text_model=$activeModel;image_model='C:\fixture-models\image'}|ConvertTo-Json|Set-Content (Join-Path $root 'desktop.json')
        }

        if($case -in @('unregistered-zim','unregistered-part')){
            Remove-Item (Join-Path $temp 'reference.json') -ErrorAction SilentlyContinue
            $env:TEST_LEGACY_ROOT=Join-Path $temp $case
            $nested=Join-Path $env:TEST_LEGACY_ROOT 'nested';New-Item -ItemType Directory $nested -Force|Out-Null
            $name=if($case -eq 'unregistered-zim'){'WIKIPEDIA.ZIM'}else{'wikipedia.ZIM.PART'}
            Set-Content (Join-Path $nested $name) 'preserve even without manifest'
        }

        $env:TEST_FAIL_INSTALL=if($case -eq 'install-fails'){'1'}else{'0'}
        $env:TEST_FAIL_LEGACY=if($case -eq 'legacy-declines'){'1'}else{'0'}
        $previousErrorAction=$ErrorActionPreference
        try {
            # PS5.1 surfaces redirected native stderr as ErrorRecords; expected child failures must reach explicit exit assertions.
            $ErrorActionPreference='Continue'
            '' | & (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $driver 2>$null
            $code=$LASTEXITCODE
        } finally {$ErrorActionPreference=$previousErrorAction}
        $events=@(Get-Content $env:TEST_AI_LOG)
        if('text' -in $events -or 'image' -in $events){throw 'Migration must not start or switch a model'}
        if($case -eq 'success' -or $case -eq 'install-fails'){
            $legacyIndex=[array]::IndexOf($events,'legacy');$skillsIndex=[array]::IndexOf($events,'old-skills');$ompIndex=[array]::IndexOf($events,'omp');$installIndex=[array]::IndexOf($events,'install')
            if($legacyIndex -lt 0 -or $skillsIndex -le $legacyIndex -or $ompIndex -le $skillsIndex -or $installIndex -le $ompIndex){throw 'Cleanup must occur before any replacement installation'}
            if($case -eq 'success' -and $code -ne 0){throw 'Successful migration failed'}
            if($case -eq 'install-fails' -and $code -eq 0){throw 'Replacement install failure was falsely reported as complete'}
            if($case -eq 'success' -and 'retire' -notin $events){throw 'Retirement did not follow successful installation'}
            if($case -eq 'install-fails' -and 'retire' -in $events){throw 'Retired old text after a failed replacement install'}
        }else{
            if($code -eq 0 -or 'omp' -in $events -or 'old-skills' -in $events -or 'install' -in $events){throw "$case must block later cleanup and installation"}
            if($case -in @('linked-weights','unregistered-zim','unregistered-part') -and 'legacy' -in $events){throw 'Active linked weights must block ALL deletion'}
        }
    }
    & (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') -CandidatePaths @('C:\legacy') -ProtectedPaths @('C:\wiki')
    $blocked=$false
    try {& (Join-Path $PSScriptRoot 'Assert-MigrationPaths.ps1') -CandidatePaths @('C:\legacy') -ProtectedPaths @('C:\legacy\wiki.zim')}catch{$blocked=$true}
    if(-not $blocked){throw 'Active corpus overlap was not blocked'}
    Write-Host 'AI-only migration stages passed: destructive-first order, decline gate, legacy-before-OMP and no unrelated stage.'
}finally{
    foreach($key in $old.Keys){[Environment]::SetEnvironmentVariable($key,$old[$key],'Process')}
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
