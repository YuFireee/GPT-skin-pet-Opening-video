param([string]$MaterialDirectory=$env:SAKURA_MATERIALS)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskApp=Join-Path $taskRoot 'sakura-studio'
if(!$MaterialDirectory){$MaterialDirectory=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'SakuraStudio\materials'}
$taskMaterials=[IO.Path]::GetFullPath($MaterialDirectory)
if($taskMaterials -eq $taskRoot -or $taskMaterials.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Keep personal materials outside the public repository.'}
$taskNode=(Get-Command node -ErrorAction Stop).Source
$taskMajor=[int]((& $taskNode --version).TrimStart('v').Split('.')[0])
if($taskMajor -lt 22){throw 'Node.js 22 or later is required.'}
$taskManifestFile=Join-Path $taskMaterials 'manifest.json'
if(!(Test-Path -LiteralPath $taskManifestFile -PathType Leaf)){throw 'External materials are not configured. Set SAKURA_MATERIALS or pass -MaterialDirectory to a folder containing manifest.json. See materials/README.md.'}
$taskManifest=Get-Content -LiteralPath $taskManifestFile -Raw -Encoding UTF8|ConvertFrom-Json
if(!$taskManifest.entries){throw 'External material manifest has no entries'}
$taskRequired=Get-Content -LiteralPath (Join-Path $taskRoot 'materials\manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$taskTargets=@($taskManifest.entries|ForEach-Object target)
if(@($taskTargets|Select-Object -Unique).Count -ne $taskTargets.Count){throw 'Duplicate external material target'}
if(@(Compare-Object @($taskRequired.entries|ForEach-Object target) $taskTargets).Count){throw 'External manifest must cover exactly the documented material targets'}
$taskCopies=@(foreach($entry in $taskManifest.entries){
 $taskSource=[IO.Path]::GetFullPath((Join-Path $taskMaterials $entry.source))
 $taskTarget=[IO.Path]::GetFullPath((Join-Path $taskApp $entry.target))
 if(!$taskSource.StartsWith($taskMaterials+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or !$taskTarget.StartsWith($taskApp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Material path outside repository'}
 if($entry.target -notmatch '^(assets/|quota-pet/assets/|quota-pet/preview\.png$)' -or $entry.source -match '(^|[\\/])\.\.([\\/]|$)' -or $entry.target -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Unexpected material target'}
 if($entry.sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Invalid material hash'}
 if(!(Test-Path -LiteralPath $taskSource -PathType Leaf)){throw ('Missing material: '+$entry.source+'. Restore it under materials/ before preparing the app.')}
 if((Get-FileHash -LiteralPath $taskSource -Algorithm SHA256).Hash -ne $entry.sha256){throw ('Material integrity mismatch: '+$entry.source)}
 @{source=$taskSource;target=$taskTarget;hash=$entry.sha256}
})
foreach($entry in $taskCopies){
 $taskParent=Split-Path -Parent $entry.target
 New-Item -ItemType Directory -Path $taskParent -Force|Out-Null
 Copy-Item -LiteralPath $entry.source -Destination $entry.target -Force
 if((Get-FileHash -LiteralPath $entry.target -Algorithm SHA256).Hash -ne $entry.hash){throw 'Material copy mismatch'}
}
$taskLocal=@{schema=1;entries=@($taskManifest.entries|ForEach-Object {@{source=$_.source;target=$_.target;sha256=$_.sha256;bytes=$_.bytes}})}
[IO.File]::WriteAllText((Join-Path $taskApp 'materials.local.json'),($taskLocal|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
$taskGenericOpening=Join-Path $taskApp 'assets/generic-opening.flag'
if($taskManifest.openingOverlay -eq 'petals-only'){
 [IO.File]::WriteAllText($taskGenericOpening,'User supplied opening: corner petals only.',[Text.Encoding]::ASCII)
}elseif(Test-Path -LiteralPath $taskGenericOpening){Remove-Item -LiteralPath $taskGenericOpening -Force}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $taskApp 'build-visual.ps1')
if($LASTEXITCODE){throw 'Native compilation failed'}
'Materials verified and native launchers compiled.'
