param([string]$FFmpeg='ffmpeg',[string]$FFprobe='ffprobe')
$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$taskCase=Join-Path $taskRoot ('reports/user-material-fixture-'+[Guid]::NewGuid().ToString('N'))
$taskRepo=Join-Path $taskCase 'source'
$taskInputs=Join-Path $taskCase 'inputs'
$taskOutput=Join-Path $taskCase 'materials'
[IO.Directory]::CreateDirectory($taskRepo)|Out-Null
[IO.Directory]::CreateDirectory($taskInputs)|Out-Null
foreach($name in @('package.json','package-lock.json','LICENSE')){Copy-Item -LiteralPath (Join-Path $taskRoot $name) -Destination (Join-Path $taskRepo $name)}
# Copy only required build/import sources. No real images, account state, or app launch.
foreach($name in @('tools','materials','sakura-studio')){
 $taskSource=Join-Path $taskRoot $name
 foreach($file in Get-ChildItem -LiteralPath $taskSource -Recurse -File){
  $relative=$file.FullName.Substring($taskSource.Length+1)
  if($relative -match '(^|[\\/])(state|assets)([\\/]|$)' -or $file.Extension -in @('.exe','.mp4','.png','.jpg','.ico','.wav')){continue}
  $dest=Join-Path (Join-Path $taskRepo $name) $relative
  [IO.Directory]::CreateDirectory((Split-Path -Parent $dest))|Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $dest
 }
}
Add-Type -AssemblyName System.Drawing
$taskTheme=Join-Path $taskInputs 'theme.png'
$bitmap=New-Object Drawing.Bitmap(960,540)
$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$graphics.Clear([Drawing.Color]::DarkSlateBlue);$bitmap.Save($taskTheme,[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
foreach($state in @('idle','executing','confirmation')){foreach($suffix in @('','-blink')){
 $bitmap=New-Object Drawing.Bitmap(512,512)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try{$graphics.Clear([Drawing.Color]::Transparent);$graphics.FillEllipse([Drawing.Brushes]::Pink,90,60,330,400);$graphics.FillRectangle([Drawing.Brushes]::Purple,170,180,30,8);$bitmap.Save((Join-Path $taskInputs ($state+$suffix+'.png')),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
}}
$taskMovie=Join-Path $taskInputs 'opening.mp4'
& $FFmpeg -hide_banner -loglevel error -nostdin -n -f lavfi -i 'testsrc2=s=640x360:r=24:d=0.8' -c:v libx264 -pix_fmt yuv420p $taskMovie
if($LASTEXITCODE){throw 'Synthetic movie fixture failed.'}
$taskArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $taskRepo 'tools/create-user-materials.ps1'),'-ThemeImage',$taskTheme,'-OpeningVideo',$taskMovie,'-CharacterDirectory',$taskInputs,'-OutputDirectory',$taskOutput,'-MaterialNotice','Synthetic test shapes and generated color movie; no user artwork.','-FFmpeg',$FFmpeg,'-FFprobe',$FFprobe)
& powershell.exe @taskArgs
if($LASTEXITCODE){throw 'Material generation failed.'}
$manifest=Get-Content -LiteralPath (Join-Path $taskOutput 'manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.entries.Count -ne 117 -or $manifest.openingOverlay -ne 'petals-only'){throw 'Generated material contract mismatch.'}
foreach($entry in $manifest.entries){if((Get-FileHash -LiteralPath (Join-Path $taskOutput $entry.source)).Hash -ne $entry.sha256){throw 'Generated hash mismatch.'}}
$probe=((& $FFprobe -v error -show_streams -of json (Join-Path $taskOutput 'theme/sakura-opening.mp4')) -join "`n")|ConvertFrom-Json
if($probe.streams[0].codec_name -ne 'h264' -or $probe.streams[0].width -ne 640){throw 'Movie codec mismatch or unexpected upscale.'}
$expectedEnd=Join-Path $taskInputs 'expected-final.png'
& $FFmpeg -hide_banner -loglevel error -nostdin -n -i (Join-Path $taskOutput 'theme/sakura-opening.mp4') -vf reverse -frames:v 1 $expectedEnd
if($LASTEXITCODE -or (Get-FileHash -LiteralPath $expectedEnd).Hash -ne (Get-FileHash -LiteralPath (Join-Path $taskOutput 'theme/sakura-opening.end.png')).Hash){throw 'Extracted ending was not the actual final frame.'}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $taskRepo 'tools/prepare.ps1') -MaterialDirectory $taskOutput
if($LASTEXITCODE){throw 'Generated materials cannot be imported/compiled.'}
if(!(Test-Path -LiteralPath (Join-Path $taskRepo 'sakura-studio/assets/generic-opening.flag'))){throw 'Generic video mode was not installed.'}
if(!(Test-Path -LiteralPath (Join-Path $taskRepo 'sakura-studio/assets/sakura-control-preview.jpg'))){throw 'Static preview was not built.'}
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$wpf=Join-Path $framework 'WPF'
$loopCheck=Join-Path $taskRepo 'sakura-studio/GenericLoopCheck.exe'
& (Join-Path $framework 'csc.exe') /nologo /target:exe ('/out:'+$loopCheck) ('/reference:'+(Join-Path $wpf 'PresentationFramework.dll')) ('/reference:'+(Join-Path $wpf 'PresentationCore.dll')) ('/reference:'+(Join-Path $wpf 'WindowsBase.dll')) ('/reference:'+(Join-Path $framework 'System.Xaml.dll')) (Join-Path $taskRepo 'sakura-studio/LoadingLoop.cs') (Join-Path $PSScriptRoot 'GenericLoopCheck.cs')
if($LASTEXITCODE){throw 'Generic waiting overlay fixture did not compile.'}
& $loopCheck (Join-Path $taskOutput 'theme/sakura-opening.end.png')
if($LASTEXITCODE){throw 'Generic overlay rendered incorrectly.'}
& node (Join-Path $taskRepo 'tools/audit.mjs') --runtime
if($LASTEXITCODE){throw 'Generated runtime did not pass source/material audit.'}
# A different input codec and PCM audio must become H.264/AAC.
$audioMovie=Join-Path $taskInputs 'with-audio.avi'
& $FFmpeg -hide_banner -loglevel error -nostdin -n -f lavfi -i 'color=c=navy:s=640x360:r=24:d=0.8' -f lavfi -i 'sine=frequency=440:sample_rate=22050:duration=0.8' -c:v mpeg4 -c:a pcm_s16le -shortest $audioMovie
if($LASTEXITCODE){throw 'Audio fixture creation failed.'}
$audioArgs=$taskArgs.Clone();$audioArgs[[Array]::IndexOf($audioArgs,'-OpeningVideo')+1]=$audioMovie
$audioOutput=Join-Path $taskCase 'audio-materials';$audioArgs[[Array]::IndexOf($audioArgs,'-OutputDirectory')+1]=$audioOutput
& powershell.exe @audioArgs
if($LASTEXITCODE){throw 'Audio video material generation failed.'}
$audioProbe=((& $FFprobe -v error -show_streams -of json (Join-Path $audioOutput 'theme/sakura-opening.mp4')) -join "`n")|ConvertFrom-Json
if(!@($audioProbe.streams|Where-Object {$_.codec_name -eq 'aac'}).Count -or !@($audioProbe.streams|Where-Object {$_.codec_name -eq 'h264'}).Count){throw 'Input video/audio were not transcoded to H.264/AAC.'}
# Existing output must be rejected without changing existing data.
$hashBefore=(Get-FileHash -LiteralPath (Join-Path $taskOutput 'manifest.json')).Hash
$previousPreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe @taskArgs 2>$null|Out-Null;$rejected=$LASTEXITCODE}finally{$ErrorActionPreference=$previousPreference}
if($rejected -eq 0 -or (Get-FileHash -LiteralPath (Join-Path $taskOutput 'manifest.json')).Hash -ne $hashBefore){throw 'Existing material output was overwritten.'}
# Opaque plates must fail rather than silently install an ugly square background.
$bitmap=New-Object Drawing.Bitmap(512,512);$graphics=[Drawing.Graphics]::FromImage($bitmap)
try{$graphics.Clear([Drawing.Color]::White);$bitmap.Save((Join-Path $taskInputs 'idle.png'),[Drawing.Imaging.ImageFormat]::Png)}finally{$graphics.Dispose();$bitmap.Dispose()}
$invalidArgs=$taskArgs.Clone();$invalidArgs[[Array]::IndexOf($invalidArgs,'-OutputDirectory')+1]=Join-Path $taskCase 'invalid-materials'
try{$ErrorActionPreference='Continue';& powershell.exe @invalidArgs 2>$null|Out-Null;$rejected=$LASTEXITCODE}finally{$ErrorActionPreference=$previousPreference}
if($rejected -eq 0 -or (Test-Path -LiteralPath (Join-Path $taskCase 'invalid-materials/manifest.json'))){throw 'Opaque character artwork was accepted.'}
$report=@{passed=$true;materialFiles=117;frames=97;mediaCodec='h264';audioCodec='aac';differentInputCodecTranscoded=$true;actualFinalFrameVerified=$true;runtimeAudit=$true;originalResolutionPreserved=$true;silentVideoAccepted=$true;genericOpeningInstalled=$true;genericOpeningRendered=$true;previewGenerated=$true;existingOutputProtected=$true;opaqueCharacterRejected=$true;scope='Synthetic local images and generated short test clips, full material generation, integrity checks, import, native compilation and waiting overlay rendering. No model, real application or account CLI was launched.'}
$report|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskRoot 'reports/user-material-checks.json') -Encoding UTF8
$report|ConvertTo-Json
