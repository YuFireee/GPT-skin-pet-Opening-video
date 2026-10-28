$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$framework=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$wpf=Join-Path $framework 'WPF'
$out=Join-Path $root 'reports/VideoFullscreenFixture.exe'
$references=@('PresentationFramework','PresentationCore','WindowsBase','UIAutomationClient','UIAutomationTypes')|ForEach-Object {'/reference:'+(Join-Path $wpf ($_+'.dll'))}
& (Join-Path $framework 'csc.exe') /nologo /target:exe /main:VideoFullscreenFixture ('/out:'+$out) ('/reference:'+(Join-Path $framework 'System.Xaml.dll')) @references (Join-Path $PSScriptRoot 'VideoFullscreenFixture.cs') (Join-Path $root 'sakura-studio/quota-pet/runtime/VideoFullscreenProbe.cs')
if($LASTEXITCODE){throw 'Probe fixture build failed'}
& $out (Join-Path $root 'sakura-studio/quota-pet/runtime/VideoFullscreenProbe.exe')
if($LASTEXITCODE){throw 'Probe fixture failed'}
