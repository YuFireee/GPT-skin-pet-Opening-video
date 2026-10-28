param(
 [Parameter(Mandatory=$true)][string]$ThemeImage,
 [Parameter(Mandatory=$true)][string]$OpeningVideo,
 [Parameter(Mandatory=$true)][string]$CharacterDirectory,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [Parameter(Mandatory=$true)][string]$MaterialNotice,
 [string]$FFmpeg='ffmpeg', [string]$FFprobe='ffprobe'
)
$ErrorActionPreference='Stop'
$taskRoot=[IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$taskOutput=[IO.Path]::GetFullPath($OutputDirectory)
if($taskOutput -eq $taskRoot -or $taskOutput.StartsWith($taskRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Material output must be outside the public repository.'}
if(Test-Path -LiteralPath $taskOutput){throw 'Output already exists. Choose a new empty directory; existing materials are never overwritten.'}
if([string]::IsNullOrWhiteSpace($MaterialNotice)){throw 'Describe the actual origin and permitted use of your inputs; this tool does not grant rights.'}
$ThemeImage=(Resolve-Path -LiteralPath $ThemeImage).Path
$OpeningVideo=(Resolve-Path -LiteralPath $OpeningVideo).Path
$CharacterDirectory=(Resolve-Path -LiteralPath $CharacterDirectory).Path
foreach($name in @('idle','executing','confirmation')){foreach($suffix in @('','-blink')){if(!(Test-Path -LiteralPath (Join-Path $CharacterDirectory ($name+$suffix+'.png')) -PathType Leaf)){throw ('Missing generated character plate: '+$name+$suffix+'.png')}}}
$taskFFmpeg=(Get-Command $FFmpeg -ErrorAction Stop).Source
$taskFFprobe=(Get-Command $FFprobe -ErrorAction Stop).Source
$taskEncoders=((& $taskFFmpeg -hide_banner -encoders 2>$null) -join "`n")
$taskFilters=((& $taskFFmpeg -hide_banner -filters 2>$null) -join "`n")
if($taskEncoders -notmatch '\blibx264\b' -or $taskEncoders -notmatch '\baac\b' -or $taskEncoders -notmatch '\bpng\b' -or $taskFilters -notmatch '\breverse\b' -or $taskFilters -notmatch '\bscale\b'){throw 'Use a complete FFmpeg build with libx264, AAC, PNG, scale and reverse. Some editor-bundled builds omit these features.'}
$taskCompiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if(!(Test-Path -LiteralPath $taskCompiler)){throw 'Windows x64 .NET Framework compiler is required.'}
$taskProbeRaw=& $taskFFprobe -v error -show_format -show_streams -of json $OpeningVideo
if($LASTEXITCODE -ne 0){throw 'Cannot inspect supplied opening video.'}
$taskProbe=($taskProbeRaw -join "`n")|ConvertFrom-Json
$taskDuration=[double]::Parse([string]$taskProbe.format.duration,[Globalization.CultureInfo]::InvariantCulture)
$taskVideo=@($taskProbe.streams|Where-Object codec_type -eq 'video')
if(!$taskVideo.Count -or $taskDuration -lt .5 -or $taskDuration -gt 30){throw 'Opening must contain video and last 0.5..30 seconds.'}
if($taskVideo[0].width/$taskVideo[0].height -lt 1.3){throw 'Use a landscape opening video.'}
New-Item -ItemType Directory -Path $taskOutput|Out-Null
$taskBuilder=Join-Path $taskOutput '.material-builder.exe'
try{
 & $taskCompiler /nologo /target:exe /optimize+ /reference:System.Drawing.dll ('/out:'+$taskBuilder) (Join-Path $PSScriptRoot 'BuildUserMaterials.cs')
 if($LASTEXITCODE){throw 'Material helper compilation failed.'}
 & $taskBuilder $ThemeImage $CharacterDirectory $taskOutput
 if($LASTEXITCODE){throw 'Character image validation or generation failed.'}
}finally{if(Test-Path -LiteralPath $taskBuilder){Remove-Item -LiteralPath $taskBuilder -Force}}
$taskMovie=Join-Path $taskOutput 'theme/sakura-opening.mp4'
& $taskFFmpeg -hide_banner -loglevel error -nostdin -n -i $OpeningVideo -map 0:v:0 -map '0:a:0?' -vf "scale=w='min(1920,iw)':h='min(1080,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2" -c:v libx264 -crf 18 -preset medium -threads 2 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart $taskMovie
if($LASTEXITCODE){throw 'Opening conversion failed.'}
& $taskFFmpeg -hide_banner -loglevel error -nostdin -n -i $taskMovie -frames:v 1 (Join-Path $taskOutput 'theme/sakura-opening.poster.png')
if($LASTEXITCODE){throw 'Poster extraction failed.'}
# Decode from EOF, then reverse that short tail, to obtain the actual final decoded frame.
& $taskFFmpeg -hide_banner -loglevel error -nostdin -n -sseof -0.5 -i $taskMovie -vf reverse -frames:v 1 (Join-Path $taskOutput 'theme/sakura-opening.end.png')
if($LASTEXITCODE){throw 'Last frame extraction failed.'}
$taskUTF8=[Text.UTF8Encoding]::new($false)
$taskNotice='User-provided / user-generated local materials. '+$MaterialNotice+"`nNot bundled in public source. AI generation does not establish rights to referenced characters or logos."
$taskRequired=Get-Content -LiteralPath (Join-Path $taskRoot 'materials/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
foreach($entry in $taskRequired.entries){
 $taskFile=[IO.Path]::GetFullPath((Join-Path $taskOutput $entry.source))
 if(!$taskFile.StartsWith($taskOutput+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $entry.source -match '(^|[\\/])\.\.([\\/]|$)'){throw 'Unexpected template path'}
 if(!(Test-Path -LiteralPath $taskFile)){
  [IO.Directory]::CreateDirectory((Split-Path -Parent $taskFile))|Out-Null
  $taskText=if($entry.source -eq 'pet/quotes.json'){'["Take a short break.","Remember to save your work.","One step at a time."]'}elseif($entry.source -eq 'pet/quote-layouts.json'){'{"version":1,"quotes":[]}'}elseif($entry.source -match '\.(txt|md)$'){$taskNotice}else{throw ('Generator did not create required material: '+$entry.source)}
  [IO.File]::WriteAllText($taskFile,$taskText,$taskUTF8)
 }
}
$taskEntries=@(foreach($entry in $taskRequired.entries){$taskFile=Join-Path $taskOutput $entry.source;@{source=$entry.source;target=$entry.target;bytes=(Get-Item -LiteralPath $taskFile).Length;sha256=(Get-FileHash -LiteralPath $taskFile -Algorithm SHA256).Hash.ToLowerInvariant()}})
$taskManifest=@{schema=1;openingOverlay='petals-only';creation='user-inputs-and-generated-plates';entries=$taskEntries}
[IO.File]::WriteAllText((Join-Path $taskOutput 'manifest.json'),($taskManifest|ConvertTo-Json -Depth 6),$taskUTF8)
'Created '+$taskEntries.Count+' local materials. Import with tools/prepare.ps1 -MaterialDirectory "'+$taskOutput+'".'
