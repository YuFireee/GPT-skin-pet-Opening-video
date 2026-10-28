$script:shortcutActions=@('none','quota','report','refresh','settings','url')
$script:shortcutLabels=@('不显示','额度卡片','Token 日报','刷新额度','桌宠设置','HTTPS 网站')
function Test-WidgetWebLink([string]$Url) {
  if(!$Url -or $Url.Length-gt 2048 -or $Url-match '[\x00-\x20\\]'){return $false}
  $uri=$null
  return [Uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme-eq 'https' -and !!$uri.Host -and !$uri.UserInfo
}
function ConvertTo-WidgetShortcuts($Entries) {
  $result=@()
  foreach($entry in @($Entries|Select-Object -First 3)){
    if(!$entry -or $entry.action-notin $script:shortcutActions){continue}
    $label=([string]$entry.label -replace '[\r\n\t]',' ').Trim();if($label.Length-gt 16){$label=$label.Substring(0,16)}
    if($entry.action-eq 'url' -and !(Test-WidgetWebLink $entry.url)){continue}
    $result+=@{label=$label;action=[string]$entry.action;url=$(if($entry.action-eq 'url'){$entry.url}else{''})}
  }
  return $result
}
function Open-WidgetWebLink([string]$Url,[scriptblock]$Opener=$null) {
  if(!(Test-WidgetWebLink $Url)){return $false}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($now-$script:lastShortcutOpen-lt 2000){return $false}
  $script:lastShortcutOpen=$now
  try{
    if($Opener){& $Opener $Url;return $true}
    $progId=try{(Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction Stop).ProgId}catch{'https'}
    if(!$progId -or !(Test-Path -LiteralPath ('Registry::HKEY_CLASSES_ROOT\'+$progId+'\shell\open\command'))){throw '未检测到 HTTPS 默认浏览器，请在 Windows 设置中选择浏览器。'}
    Start-Process -FilePath $Url -ErrorAction Stop|Out-Null
    return $true
  }catch{
    if($script:settingsPanel){$script:settingsPanel.FindName('SettingsFeedback').Text='网站未打开：请检查默认浏览器。已停止，不会重试。'}
    return $false
  }
}
function Invoke-WidgetShortcut($Entry) {
  switch($Entry.action){
    'quota' {if(!$script:quotaCard){Open-QuotaCard}}
    'report' {Close-QuotaCard -Immediate;Open-TokenPanel}
    'refresh' {Request-Refresh}
    'settings' {Close-QuotaCard -Immediate;Open-WidgetSettingsPanel}
    'url' {Open-WidgetWebLink $Entry.url|Out-Null}
  }
}
function Update-CardShortcuts {
  if(!$script:quotaCard){return}
  $hostPanel=$script:quotaCard.FindName('CardShortcuts');$key=ConvertTo-Json -InputObject @($script:shortcuts) -Compress
  if($hostPanel.Tag-eq $key){return};$hostPanel.Tag=$key;$hostPanel.Children.Clear()
  foreach($entry in @($script:shortcuts)){
    if($entry.action-eq 'none'){continue}
    $button=[Windows.Controls.Button]::new();$button.Content=$entry.label
    if(!$button.Content){$button.Content=$script:shortcutLabels[[Array]::IndexOf($script:shortcutActions,[string]$entry.action)]}
    $button.Tag=$entry;$button.Margin='0,2,5,2';$button.Padding='9,5';$button.FontSize=11
    $button.Add_Click({param($sender,$event)Invoke-WidgetShortcut $sender.Tag});$hostPanel.Children.Add($button)|Out-Null
  }
}
function Get-WidgetAnnouncementText([switch]$Detailed) {
  if(!$script:announcementsOn){return '第三方公告已关闭；账户额度提醒不受影响。'}
  try{
    $file=Join-Path $script:dataDir 'reset-announcements.json';$stamp=[IO.File]::GetLastWriteTimeUtc($file).Ticks
    if($stamp-ne $script:announcementUiStamp){$script:announcementUiData=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json;$script:announcementUiStamp=$stamp}
    $packet=$script:announcementUiData
    if(!$packet){return '等待获取公告；不会因此改变账户额度。'}
  }catch{return '等待获取公告；不会因此改变账户额度。'}
  $lines=@()
  foreach($entry in @($packet.scheduled,$packet.latest)){
    if(!$entry){continue}
    $kind=if($entry.kind-eq 'banked'){'储备重置额度'}else{'额外重置'}
    $date=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$entry.at).ToLocalTime().ToString('MM-dd HH:mm')
    $lines+=if($entry.scheduled){$date+' 公告计划：'+$kind+'（未确认执行）'}else{$date+' 第三方记录：'+$kind}
    if($Detailed){$lines+=[string]$entry.text}
    if(!$Detailed){break}
  }
  if(!$lines.Count){$lines+='暂无可展示的重置公告'}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  if($packet.error -or !$packet.checkedAt -or $now-[long]$packet.checkedAt-gt 3600000){$lines+='缓存可能过期；以来源和账户实际额度为准。'}
  elseif($Detailed){$lines+='检查于 '+[DateTimeOffset]::FromUnixTimeMilliseconds([long]$packet.checkedAt).ToLocalTime().ToString('HH:mm')+'；不代表本账户已恢复。'}
  return $lines-join [Environment]::NewLine
}
function Update-CardAnnouncements {
  if($script:quotaCard){$script:quotaCard.FindName('CardAnnouncement').Text=Get-WidgetAnnouncementText}
}
function Get-WidgetDiagnostics {
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();$lines=@()
  $lines+='查询程序：'+$(if($script:config.codexPath -and [IO.File]::Exists($script:config.codexPath)){'路径存在'}else{'未找到；不会自动打开应用'})
  try{$worker=Get-Content -LiteralPath (Join-Path $script:dataDir 'worker-status.json') -Raw -Encoding UTF8|ConvertFrom-Json}catch{$worker=$null}
  $lines+='额度工作进程：'+$(if($worker -and $now-[long]$worker.at-ge 0 -and $now-[long]$worker.at-lt 5000){'心跳正常'}else{'离线或心跳过期'})
  $lines+='账户额度：'+$(if($script:status.queryOk -and $script:status.ok){if($now-[long]$script:status.observedAt-ge 0 -and $now-[long]$script:status.observedAt-lt 180000){'有效'}else{'数据已过期，请手动刷新'}}else{'尚未读到有效数据'})
  if($script:status.error){$lines+='查询说明：'+[string]$script:status.error}
  $lines+='角色状态（日志推断）：'+$(switch($script:dialogAnimationState){'running'{'正在执行'}'confirmation'{'待确认（剪刀手）'}default{'常态 / 无新鲜信号'}})
  $data=Get-ActivitySnapshot
  $lines+='Token 日志：'+$(if($data){'本机快照可用（近7天 / 约5小时）'}else{'尚无快照'})
  try{$health=Get-Content -LiteralPath (Join-Path $script:dataDir 'resource-health.json') -Raw -Encoding UTF8|ConvertFrom-Json;$sample=@($health.samples)[-1];if($sample){$lines+='桌宠内存（最近采样）：'+$sample.privateMB+' MB'}}catch{}
  return $lines-join [Environment]::NewLine
}
function Update-SettingsDiagnostics {
  if(!$script:settingsPanel){return}
  $script:settingsPanel.FindName('SettingsDiagnostics').Text=Get-WidgetDiagnostics
  $script:settingsPanel.FindName('SettingsAnnouncementText').Text=Get-WidgetAnnouncementText -Detailed
}
function Open-WidgetSettingsPanel {
  if($script:settingsPanel){$script:settingsPanel.Activate()|Out-Null;return}
  Close-QuotaCard -Immediate
  if($script:context){$script:context.IsOpen=$false}
  $panel=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'settings-panel.xaml')))
  $script:settingsPanel=$panel
  $panel.MaxHeight=[Math]::Max(300,[Windows.SystemParameters]::WorkArea.Height-20)
  if($script:window.IsVisible){$panel.Owner=$script:window}
  $panel.Topmost=[bool]$script:desktopTopmost
  $panel.FindName('SettingsFollow').SelectedIndex=[int][bool]$script:followHost
  foreach($pair in @(@('SettingsTopmost','desktopTopmost'),@('SettingsSound','soundOn'),@('SettingsIdle','idleAnimationOn'),@('SettingsColorPaused','colorPaused'),@('SettingsAlerts','quotaAlertsOn'),@('SettingsAnnouncements','announcementsOn'))){
    $panel.FindName($pair[0]).IsChecked=[bool](Get-Variable -Scope Script -Name $pair[1] -ValueOnly)
  }
  $panel.FindName('SettingsScale').Value=$script:scale;$panel.FindName('SettingsVolume').Value=$script:soundVolume
  $panel.FindName('SettingsThreshold').SelectedIndex=[Array]::IndexOf(@(10,20,30),[int]$script:quotaAlertThreshold)
  $colorModes=@('original','linked','rainbow','mixed')
  $panel.FindName('SettingsColor').SelectedIndex=[Array]::IndexOf($colorModes,[string]$script:colorMode)
  $script:shortcutEditors=@()
  for($i=0;$i-lt 3;$i++){
    $entry=@($script:shortcuts)[$i]
    $row=[Windows.Controls.StackPanel]::new();$row.Margin='0,0,0,12'
    $title=[Windows.Controls.TextBlock]::new();$title.Text='按钮 '+($i+1);$title.FontWeight='SemiBold';$row.Children.Add($title)|Out-Null
    $label=[Windows.Controls.TextBox]::new();$label.MaxLength=16;$label.Text=[string]$entry.label;$label.ToolTip='按钮名称（最多16字）';$row.Children.Add($label)|Out-Null
    $combo=[Windows.Controls.ComboBox]::new();foreach($name in $script:shortcutLabels){$combo.Items.Add($name)|Out-Null}
    $combo.SelectedIndex=[Math]::Max(0,[Array]::IndexOf($script:shortcutActions,[string]$entry.action));$row.Children.Add($combo)|Out-Null
    $url=[Windows.Controls.TextBox]::new();$url.MaxLength=2048;$url.Text=[string]$entry.url;$url.ToolTip='https://…';$url.IsEnabled=($combo.SelectedIndex-eq 5);$combo.Tag=$url
    $combo.Add_SelectionChanged({param($sender,$event)$sender.Tag.IsEnabled=($sender.SelectedIndex-eq 5)})
    $row.Children.Add($url)|Out-Null;$panel.FindName('SettingsShortcutRows').Children.Add($row)|Out-Null
    $script:shortcutEditors+=@{Label=$label;Action=$combo;Url=$url}
  }
  $panel.FindName('CloseSettings').Add_Click({$script:settingsPanel.Close()})
  $panel.FindName('SettingsHeader').Add_MouseLeftButtonDown({try{$script:settingsPanel.DragMove()}catch{}})
  $panel.FindName('RefreshDiagnostics').Add_Click({Update-SettingsDiagnostics})
  $panel.FindName('SettingsAnnouncementSource').Add_Click({Open-WidgetWebLink 'https://codex-resets.com'|Out-Null})
  $panel.FindName('OpenLocalReport').Add_Click({$script:settingsPanel.Tag='immediate';$script:settingsPanel.Close();Open-TokenPanel})
  $panel.FindName('SaveUnifiedSettings').Add_Click({Save-UnifiedWidgetSettings})
  $panel.Add_KeyDown({param($sender,$event)if($event.Key-eq 'Escape'){$sender.Close();$event.Handled=$true}})
  $panel.Add_Closed({param($sender,$event)if([Object]::ReferenceEquals($sender,$script:settingsPanel)){$script:settingsPanel=$null;$script:shortcutEditors=@()}})
  Update-SettingsDiagnostics
  Add-QuotaTransition $panel;$panel.Show()
}
function Save-UnifiedWidgetSettings {
  $panel=$script:settingsPanel;if(!$panel){return}
  $entries=@()
  foreach($editor in $script:shortcutEditors){
    $action=$script:shortcutActions[$editor.Action.SelectedIndex]
    if($action-eq 'url' -and !(Test-WidgetWebLink $editor.Url.Text)){$panel.FindName('SettingsFeedback').Text='网站地址须为有效的 https:// 地址。尚未保存。';return}
    $entries+=@{label=$editor.Label.Text;action=$action;url=$editor.Url.Text}
  }
  $script:shortcuts=@(ConvertTo-WidgetShortcuts $entries)
  $nextFollow=($panel.FindName('SettingsFollow').SelectedIndex-eq 1)
  foreach($pair in @(@('SettingsTopmost','desktopTopmost'),@('SettingsSound','soundOn'),@('SettingsIdle','idleAnimationOn'),@('SettingsColorPaused','colorPaused'),@('SettingsAlerts','quotaAlertsOn'),@('SettingsAnnouncements','announcementsOn'))){
    Set-Variable -Scope Script -Name $pair[1] -Value ([bool]$panel.FindName($pair[0]).IsChecked)
  }
  $script:scale=[Math]::Round($panel.FindName('SettingsScale').Value,1);$script:soundVolume=$panel.FindName('SettingsVolume').Value
  $script:quotaAlertThreshold=@(10,20,30)[$panel.FindName('SettingsThreshold').SelectedIndex]
  $colorIndex=$panel.FindName('SettingsColor').SelectedIndex
  if($colorIndex-ge 0){$mode=@('original','linked','rainbow','mixed')[$colorIndex];if($mode-ne $script:colorMode){Set-WidgetColorMode $mode}}
  if(!$script:soundOn){Stop-WidgetAudio};Set-WidgetAudioVolume
  if($nextFollow-ne $script:followHost){Set-WidgetFollowHost $nextFollow -Defer}
  $script:lastPosition=$null;Set-Appearance;Update-IdleSprite;Save-Settings;Update-WidgetSettingsMenu;Update-QuotaNotice
  $panel.Topmost=[bool]$script:desktopTopmost;Tick-Widget;Update-SettingsDiagnostics
  $panel.FindName('SettingsFeedback').Text='已保存。快捷按钮会显示在额度卡片底部。'
}
