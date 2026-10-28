function Update-QuotaNotice {
  if(!$script:ui.QuotaNotice){return}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if(!$script:quotaNoticeLoaded){
    $script:quotaNoticeLoaded=$true
    try{$script:quotaNoticeSeen=(Get-Content -LiteralPath (Join-Path $script:dataDir 'quota-notice-ui.json') -Raw -Encoding UTF8|ConvertFrom-Json).id}catch{}
  }
  try{
    $file=Join-Path $script:dataDir 'quota-alerts.json';$stamp=if([IO.File]::Exists($file)){[IO.File]::GetLastWriteTimeUtc($file).Ticks}else{0}
    if($stamp -and $stamp-ne $script:quotaNoticeStamp){$script:quotaNoticeData=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json;$script:quotaNoticeStamp=$stamp}
  }catch{}
  $packet=$script:quotaNoticeData
  $events=@($packet.events|Where-Object {$_.at-ge $now-300000 -and $_.at-le $now+5000})
  $latest=if($events.Count){$events[-1]}else{$null}
  $id=if($latest){[string]$packet.state.accountKey+'|'+$latest.id}else{''}
  $eligible=$script:quotaAlertsOn -and !$script:fullscreenYielded -and $script:window.IsVisible -and $script:status.ok -and $script:status.queryOk -and $packet.state.accountKey-eq $script:status.accountKey
  if(!$script:quotaAlertsOn -and $id -and $id-ne $script:quotaNoticeSeen){
    $script:quotaNoticeSeen=$id;try{Write-WidgetJson (Join-Path $script:dataDir 'quota-notice-ui.json') @{id=$id}}catch{}
  }
  if($eligible -and $id -and $id-ne $script:quotaNoticeSeen){
    $script:quotaNoticeSeen=$id
    $script:ui.QuotaNoticeText.Text=(@(for($i=[Math]::Max(0,$events.Count-2);$i-lt $events.Count;$i++){$events[$i].text})-join [Environment]::NewLine)
    $script:ui.QuotaNotice.ToolTip=$script:ui.QuotaNoticeText.Text+' · 点击查看额度'
    $script:quotaNoticeUntil=$now+8000
    try{Write-WidgetJson (Join-Path $script:dataDir 'quota-notice-ui.json') @{id=$id}}catch{}
  }
  $script:ui.QuotaNotice.Visibility=if($eligible -and $now-lt $script:quotaNoticeUntil){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
}
