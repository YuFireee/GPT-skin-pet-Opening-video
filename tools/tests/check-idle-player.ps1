param([switch]$UsePrecompiled)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$appDir=Join-Path $root 'sakura-studio/quota-pet'
if($UsePrecompiled){Add-Type -Path (Join-Path $appDir 'runtime/WidgetNative.dll')}else{Add-Type -Path (Join-Path $appDir 'runtime/IdleSpritePlayer.cs') -ReferencedAssemblies ([Windows.Controls.Image].Assembly.Location),([Windows.Media.Imaging.BitmapImage].Assembly.Location),([Windows.Freezable].Assembly.Location),([Windows.Markup.IQueryAmbient].Assembly.Location)}
function Pump([int]$Ms){$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds($Ms);$timer.Tag=$frame;$timer.Add_Tick({param($sender,$event)$sender.Stop();$sender.Tag.Continue=$false});$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)}
$window=[Windows.Window]::new();$window.Width=240;$window.Height=260;$window.ShowActivated=$false;$window.ShowInTaskbar=$false;$window.Title='Sakura idle animation fixture'
$image=[Windows.Controls.Image]::new();$bitmap=[Windows.Media.Imaging.BitmapImage]::new([Uri](Join-Path $appDir 'assets/sakura-soft-bust.png'));$bitmap.Freeze();$image.Source=$bitmap;$window.Content=$image
$player=[SakuraIdleSpritePlayer]::new($image,$window,(Join-Path $appDir 'assets/idle-soft'))
$player.SetEnabled($true)
if($player.CachedFrames-ne 0){throw 'Hidden player decoded frames'}
$window.Show();Pump 400
if($player.Faulted -or !$player.IsPlaying -or $player.CachedFrames-ne 27){throw ('Player did not start: '+$player.LastError)}
function ImageHash { $pixels=New-Object byte[] (512*512*4);$image.Source.CopyPixels($pixels,512*4,0);$sha=[Security.Cryptography.SHA256]::Create();try{[BitConverter]::ToString($sha.ComputeHash($pixels))}finally{$sha.Dispose()} }
$normalHash=ImageHash
$frame=$player.CurrentFrame;Pump 450
if($player.CurrentFrame-eq $frame){throw 'Animation did not advance'}
$runningFrames=[IO.File]::ReadAllLines((Join-Path $appDir 'assets/executing-soft/frame-durations.txt')).Length
$player.SetState('running');Pump 150
if($player.State-ne 'running' -or $player.CachedFrames-ne $runningFrames -or !$player.IsPlaying){throw 'Execution state did not load'}
$runningHash=ImageHash
$confirmationFrames=[IO.File]::ReadAllLines((Join-Path $appDir 'assets/confirmation-soft/frame-durations.txt')).Length
$player.SetState('confirmation');Pump 100
if($player.State-ne 'confirmation' -or $player.CachedFrames-ne $confirmationFrames){throw 'Confirmation state failed'}
if((ImageHash)-eq $normalHash -or (ImageHash)-eq $runningHash){throw 'Confirmation image fell back to another state'}
$player.SetState('normal');Pump 100
. (Join-Path $appDir 'runtime/idle-sprite.ps1')
$script:idleSprite=$player;$script:dataDir=Join-Path $root 'reports/animation-state-fixture'
$null=New-Item -ItemType Directory -Force $script:dataDir
$statePath=Join-Path $script:dataDir 'dialog-state.json';$seq=0
foreach($state in @('running','confirmation','normal')){
 $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
 @{state=$state;checkedAt=$now;observedAt=$now}|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
 $seq++;[IO.File]::SetLastWriteTimeUtc($statePath,[DateTime]::UtcNow.AddSeconds($seq))
 Update-DialogAnimation;Pump 40
 if($player.State-ne $state -or $player.Faulted){throw 'Dialog snapshot did not switch animation'}
}
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
@{state='confirmation';checkedAt=($now-20000);observedAt=$now}|ConvertTo-Json|Set-Content -LiteralPath $statePath -Encoding UTF8
[IO.File]::SetLastWriteTimeUtc($statePath,[DateTime]::UtcNow.AddSeconds(10))
Update-DialogAnimation
if($player.State-ne 'normal'){throw 'Stale snapshot did not return to normal'}
$window.Hide();Pump 50
if($player.IsPlaying -or $player.CachedFrames-ne 0 -or ![Object]::ReferenceEquals($image.Source,$bitmap)){throw 'Hidden player retained frames'}
$window.Show();Pump 100;$player.SetEnabled($false)
if($player.IsPlaying -or $player.CachedFrames-ne 0){throw 'Disabled animation still loaded'}
$player.SetEnabled($true);Pump 100;$window.Hide();Pump 100
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();$before=[GC]::GetTotalMemory($true)
for($i=0;$i-lt 12;$i++){$window.Show();$player.SetState(@('normal','running','confirmation')[$i%3]);Pump 60;if(!$player.IsPlaying){throw 'Resume failed'};$window.Hide();Pump 60;if($player.CachedFrames-ne 0){throw 'Cycle retained frames'}}
[GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect();$after=[GC]::GetTotalMemory($true)
if($after-$before-gt 16MB){throw ('Retained animation memory: '+($after-$before))}
$window.Close();$player.Dispose()
$report=@{passed=$true;frames=27;runningFrames=$runningFrames;confirmationFrames=$confirmationFrames;hiddenFrames=$player.CachedFrames;cycleCount=12;managedBeforeMB=[Math]::Round($before/1MB,1);managedAfterMB=[Math]::Round($after/1MB,1);noPowerShellFrameTick=$true}
$report|ConvertTo-Json|Set-Content (Join-Path $root 'reports/idle-player-checks.json') -Encoding UTF8
$report|ConvertTo-Json -Compress
