function Initialize-IdleSprite {
  if($script:spriteFile-ne 'sakura-soft-bust.png'){return}
  $folder=Join-Path $script:appDir 'assets/idle-soft'
  if(!(Test-Path -LiteralPath (Join-Path $folder 'frame-durations.txt'))){return}
  if(!('SakuraIdleSpritePlayer' -as [type])){
    Add-Type -AssemblyName System.Xaml
    Add-Type -Path (Join-Path $script:appDir 'runtime/IdleSpritePlayer.cs') -ReferencedAssemblies ([Windows.Controls.Image].Assembly.Location),([Windows.Media.Imaging.BitmapImage].Assembly.Location),([Windows.Freezable].Assembly.Location),([Windows.Markup.IQueryAmbient].Assembly.Location)
  }
  $script:idleSprite=[SakuraIdleSpritePlayer]::new($script:ui.Girl,$script:window,$folder)
  $script:idleSprite.SetEnabled([bool]$script:idleAnimationOn)
}
function Update-IdleSprite {
  if($script:idleSprite){$script:idleSprite.SetEnabled([bool]$script:idleAnimationOn)}
}

function Update-DialogAnimation {
  if(!$script:idleSprite){return}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $next='normal'
  try{
    $file=Join-Path $script:dataDir 'dialog-state.json'
    $stamp=[IO.File]::GetLastWriteTimeUtc($file).Ticks
    if($stamp-ne $script:dialogStateStamp -and [IO.File]::Exists($file)){
      $script:dialogStateSnapshot=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8)|ConvertFrom-Json
      $script:dialogStateStamp=$stamp
    }
    $packet=$script:dialogStateSnapshot
    if($packet -and $packet.state-in @('normal','running','confirmation') -and $now-[long]$packet.checkedAt-ge 0 -and $now-[long]$packet.checkedAt-le 15000 -and $packet.observedAt -and $now-[long]$packet.observedAt-ge -60000 -and $now-[long]$packet.observedAt-le 600000){$next=[string]$packet.state}
  }catch{}
  $script:dialogAnimationState=$next
  $script:idleSprite.SetState($next)
}
