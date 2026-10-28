$ErrorActionPreference='Stop'
$studioRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
$framework=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$wpf=Join-Path $framework 'WPF'
# Generate a small, local-only preview at build time. The controller never decodes the 4K original.
$previewSource=Join-Path $studioRoot 'assets/sakura-calm-soft-portrait.png'
if(Test-Path -LiteralPath $previewSource){
 Add-Type -AssemblyName System.Drawing
 $sourceImage=$null;$thumbnail=$null;$graphics=$null
 try{
  $sourceImage=[Drawing.Image]::FromFile($previewSource)
  $thumbnail=New-Object Drawing.Bitmap(480,270)
  $graphics=[Drawing.Graphics]::FromImage($thumbnail)
  $graphics.InterpolationMode=[Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $graphics.DrawImage($sourceImage,0,0,480,270)
  $thumbnail.Save((Join-Path $studioRoot 'assets/sakura-control-preview.jpg'),[Drawing.Imaging.ImageFormat]::Jpeg)
 }finally{if($graphics){$graphics.Dispose()};if($thumbnail){$thumbnail.Dispose()};if($sourceImage){$sourceImage.Dispose()}}
}
$arguments=@('/nologo','/target:winexe','/optimize+','/platform:anycpu',('/out:'+(Join-Path $studioRoot 'SakuraVisual.exe')),('/reference:'+(Join-Path $wpf 'PresentationFramework.dll')),('/reference:'+(Join-Path $wpf 'PresentationCore.dll')),('/reference:'+(Join-Path $wpf 'WindowsBase.dll')),('/reference:'+(Join-Path $framework 'System.Xaml.dll')),(Join-Path $studioRoot 'SakuraVisual.cs'))
& (Join-Path $framework 'csc.exe') @arguments
if($LASTEXITCODE -ne 0){throw 'Native visual compilation failed.'}

$bootArguments=$arguments | ForEach-Object { $_.Replace("SakuraVisual.exe","SakuraBoot.exe").Replace("SakuraVisual.cs","SakuraBoot.cs") }
$bootArguments+=Join-Path $studioRoot "BootHandoff.cs"
$bootArguments+=Join-Path $studioRoot "MovieBoot.cs"
$bootArguments+=Join-Path $studioRoot "LoadingLoop.cs"
$bootArguments+=Join-Path $studioRoot "BootEscape.cs"
& (Join-Path $framework "csc.exe") @bootArguments
if($LASTEXITCODE -ne 0){throw "Boot animation compilation failed."}

$probeArgs=@('/nologo','/target:exe','/optimize+',('/out:'+(Join-Path $studioRoot 'quota-pet/runtime/VideoFullscreenProbe.exe')),('/reference:'+(Join-Path $wpf 'UIAutomationClient.dll')),('/reference:'+(Join-Path $wpf 'UIAutomationTypes.dll')),('/reference:'+(Join-Path $wpf 'WindowsBase.dll')),(Join-Path $studioRoot 'quota-pet/runtime/VideoFullscreenProbe.cs'))
& (Join-Path $framework 'csc.exe') @probeArgs
if($LASTEXITCODE -ne 0){throw 'Video fullscreen probe compilation failed.'}

$controlArgs=@('/nologo','/target:winexe','/optimize+',('/out:'+(Join-Path $studioRoot 'SakuraControl.exe')),'/reference:System.Windows.Forms.dll','/reference:System.Drawing.dll','/reference:System.Web.Extensions.dll',(Join-Path $studioRoot 'SakuraControl.cs'))
if(Test-Path -LiteralPath (Join-Path $studioRoot 'assets/launcher.ico')){$controlArgs+=('/win32icon:'+(Join-Path $studioRoot 'assets/launcher.ico'))}
& (Join-Path $framework 'csc.exe') @controlArgs
if($LASTEXITCODE -ne 0){throw 'Native control compilation failed.'}

& (Join-Path $framework 'csc.exe') /nologo /target:library /optimize+ ('/out:'+(Join-Path $studioRoot 'NativeTcp.dll')) (Join-Path $studioRoot 'NativeTcp.cs')
if($LASTEXITCODE -ne 0){throw 'Native TCP inspection compilation failed.'}

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $studioRoot 'build-pet-native.ps1')
if($LASTEXITCODE -ne 0){throw 'Pet native helper compilation failed.'}
