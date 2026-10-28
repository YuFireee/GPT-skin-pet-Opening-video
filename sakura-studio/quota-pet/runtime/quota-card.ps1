function Get-QuotaCapsuleBounds {
  try{
    if(!$script:window.IsVisible){return $null}
    $control=$script:ui.QuotaCapsule
    $from=$control.PointToScreen([Windows.Point]::new(0,0));$to=$control.PointToScreen([Windows.Point]::new($control.ActualWidth,$control.ActualHeight))
    $matrix=[Windows.PresentationSource]::FromVisual($script:window);$transform=$matrix.CompositionTarget.TransformFromDevice
    $a=$transform.Transform($from);$b=$transform.Transform($to)
    $width=[Math]::Abs($b.X-$a.X);$height=[Math]::Abs($b.Y-$a.Y)
    if($width-lt 1 -or $height-lt 1){return $null}
    return @{Left=[Math]::Min($a.X,$b.X);Top=[Math]::Min($a.Y,$b.Y);Width=$width;Height=$height}
  }catch{return $null}
}
function Start-QuotaMorph($Panel,$From,$To,[bool]$Closing) {
  $Panel.Resources['MorphFromWidth']=[double]$From.Width
  $Panel.Resources['MorphToWidth']=[double]$To.Width
  $duration=[TimeSpan]::FromMilliseconds($(if($Closing){180}else{240}))
  foreach($property in @('Left','Top','Width','Height')){
    $dp=[Windows.Window]::($property+'Property')
    # Width and Height are inherited FrameworkElement dependency properties.
    $animation=[Windows.Media.Animation.DoubleAnimation]::new([double]$From[$property],[double]$To[$property],$duration)
    $animation.EasingFunction=[Windows.Media.Animation.CubicEase]::new();$animation.EasingFunction.EasingMode='EaseInOut'
    $Panel.BeginAnimation($dp,$animation)
  }
  if($Panel.Content -is [Windows.Controls.Border]){
    if('SakuraCornerAnimation' -as [type]){
      $corner=[SakuraCornerAnimation]::new();$corner.From=$(if($Closing){20}else{24});$corner.To=$(if($Closing){24}else{20});$corner.Duration=$duration
      $Panel.Content.BeginAnimation([Windows.Controls.Border]::CornerRadiusProperty,$corner)
    }
    $Panel.Content.ClipToBounds=$true
  }
  $fade=[Windows.Media.Animation.DoubleAnimation]::new($(if($Closing){1.0}else{0.0}),$(if($Closing){0.0}else{1.0}),$duration)
  $transitionPanel=$Panel
  if($Closing){
    $fade.Add_Completed({$transitionPanel.Tag='immediate';$transitionPanel.Close()}.GetNewClosure())
  }else{
    $fade.Add_Completed({
      foreach($property in @('Left','Top','Width','Height')){$value=$transitionPanel.GetValue([Windows.Window]::($property+'Property'));$transitionPanel.BeginAnimation([Windows.Window]::($property+'Property'),$null);$transitionPanel.SetValue([Windows.Window]::($property+'Property'),$value)}
      if($transitionPanel.Tag-eq 'opening'){$transitionPanel.Tag='ready';$transitionPanel.IsHitTestVisible=$true}
    }.GetNewClosure())
  }
  $Panel.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
}
function Add-QuotaTransition($Panel) {
  if(!('SakuraCornerAnimation' -as [type])){
    Add-Type -Path (Join-Path $script:appDir 'runtime/PanelMorph.cs') -ReferencedAssemblies ([Windows.Controls.Border].Assembly.Location),([Windows.Freezable].Assembly.Location),([Windows.Media.Animation.AnimationTimeline].Assembly.Location)
  }
  $target=@{Left=$Panel.Left;Top=$Panel.Top;Width=$Panel.Width;Height=$Panel.Height}
  $origin=Get-QuotaCapsuleBounds
  if(!$origin){$origin=@{Left=$target.Left;Top=$target.Top;Width=$target.Width;Height=$target.Height}}
  $Panel.Tag='opening';$Panel.Opacity=0
  if($script:ui.QuotaCapsule){$script:ui.QuotaCapsule.Opacity=0}
  $Panel.Add_ContentRendered({
    param($sender,$event)
    if($sender.Tag-eq 'opening'){
      foreach($property in @('Left','Top')){if([double]::IsNaN($target[$property])){$target[$property]=$sender.$property;if([double]::IsNaN($origin[$property])){$origin[$property]=$sender.$property}}}
      Start-QuotaMorph $sender $origin $target $false
    }
  }.GetNewClosure())
  $Panel.Add_Closing({
    param($sender,$event)
    if($sender.Tag-eq 'immediate'){return}
    $event.Cancel=$true;if($sender.Tag-eq 'closing'){return}
    $sender.Tag='closing';$sender.IsHitTestVisible=$false
    $current=@{Left=$sender.Left;Top=$sender.Top;Width=$sender.Width;Height=$sender.Height}
    $back=Get-QuotaCapsuleBounds;if(!$back){$back=$current}
    Start-QuotaMorph $sender $current $back $true
  })
  $Panel.Add_Closed({
    param($sender,$event)
    foreach($property in @('Left','Top','Width','Height')){$sender.BeginAnimation([Windows.Window]::($property+'Property'),$null)}
    $sender.BeginAnimation([Windows.UIElement]::OpacityProperty,$null)
    if($sender.Content -is [Windows.Controls.Border]){$sender.Content.BeginAnimation([Windows.Controls.Border]::CornerRadiusProperty,$null)}
    if($script:ui.QuotaCapsule){$script:ui.QuotaCapsule.Opacity=1}
  })
}
function Close-QuotaCard([switch]$Immediate){
  if($script:quotaCard){if($Immediate){$script:quotaCard.Tag='immediate'};$script:quotaCard.Close()}
}
function Update-QuotaRing($Ring,$Value,$Button,[int]$Minutes,[string]$Label){
  if(!$Ring -or !$Value -or !$Button){return}
  $quota=$null
  foreach($entry in $script:status.windows){if($entry -and $entry.kind-ne 'individual' -and $entry.minutes-eq $Minutes){$quota=$entry;break}}
  $text='—';$dash=0.0
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $expired=$quota -and $null-ne $quota.resetsAt -and [double]$quota.resetsAt-gt 0 -and [double]$quota.resetsAt-le $now
  if($quota -and !$expired -and $null-ne $quota.remaining -and ([string]$quota.remaining).Trim()){
    try{
      $number=[double]$quota.remaining
      if(![double]::IsNaN($number) -and ![double]::IsInfinity($number)){
        $number=[Math]::Max(0,[Math]::Min(100,$number))
        $text=$number.ToString('0.#')+'%';$dash=$number*0.219911
      }
    }catch{}
  }
  $Value.Text=$text
  $Button.ToolTip=$Label+'剩余 '+$text+' · 点击查看额度'
  # Reuse each ring's Freezable collection on heartbeat updates.
  $segments=$Ring.StrokeDashArray
  if(!$segments -or $segments.IsFrozen -or $segments.Count-ne 2){$Ring.StrokeDashArray=[Windows.Media.DoubleCollection]::new([double[]]@($dash,22.0))}
  elseif([Math]::Abs($segments[0]-$dash)-gt 0.0001){$segments[0]=$dash}
}
function Update-QuotaCapsule {
  Update-QuotaRing $script:ui.CapsuleRing $script:ui.CapsuleValue $script:ui.ShortQuotaButton 300 '5小时'
  Update-QuotaRing $script:ui.CapsuleWeekRing $script:ui.CapsuleWeekValue $script:ui.WeekQuotaButton 10080 '每周'
  if(!$script:quotaCard -or !$script:quotaCard.IsVisible){return}
  foreach($prefix in @('Short','Week')){
    $script:quotaCard.FindName('Card'+$prefix+'Value').Text=$script:ui[$prefix+'Left'].Text
    $script:quotaCard.FindName('Card'+$prefix+'Label').Text=$script:ui[$prefix+'Label'].Text+'剩余'
    $script:quotaCard.FindName('Card'+$prefix+'Reset').Text=$script:ui[$prefix+'Reset'].Text
  }
  $script:quotaCard.FindName('QuotaPlan').Text=if($script:status.planLabel){$script:status.planLabel}else{'订阅额度'}
  if(Get-Command Update-CardAnnouncements -ErrorAction SilentlyContinue){Update-CardAnnouncements}
  if(Get-Command Update-CardShortcuts -ErrorAction SilentlyContinue){Update-CardShortcuts}
  $data=Get-ActivitySnapshot
  $seven=0.0;$five=0.0
  if($data){foreach($entry in $data.days.PSObject.Properties){$seven+=[double]$entry.Value};foreach($entry in $data.recentMinutes.PSObject.Properties){$five+=[double]$entry.Value}}
  $script:quotaCard.FindName('CardSevenTokens').Text=if($data){$seven.ToString('N0')}else{'—'}
  $script:quotaCard.FindName('CardFiveTokens').Text=if($data){$five.ToString('N0')}else{'—'}
  $script:quotaCard.FindName('CardFreshness').Text=$script:ui.Status.Text+'。Token 为本机已记录量，首次历史可不完整。'
}
function Open-QuotaCard {
  if($script:quotaCard){if($script:quotaCard.Tag-ne 'closing'){Close-QuotaCard};return}
  if(!$script:collapsed){Hide-Quota}
  $panel=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'quota-card.xaml'),[Text.Encoding]::UTF8))
  $panel.Height=[Math]::Min($panel.Height,[Windows.SystemParameters]::WorkArea.Height-20)
  $script:quotaCard=$panel
  if($script:window -and $script:window.IsVisible){$panel.Owner=$script:window}
  $panel.Topmost=[bool]$script:desktopTopmost
  $panel.FindName('CollapseCard').Add_Click({Close-QuotaCard})
  $panel.FindName('CardSettings').Add_Click({Close-QuotaCard -Immediate;Open-WidgetSettingsPanel})
  $panel.FindName('AnnouncementLink').Add_Click({Open-WidgetWebLink 'https://codex-resets.com'})
  $panel.FindName('OpenReport').Add_Click({Close-QuotaCard -Immediate;Open-TokenPanel})
  $panel.FindName('RefreshCard').Add_Click({Request-Refresh;$script:quotaCard.FindName('CardFreshness').Text='正在刷新额度…'})
  $panel.Add_Deactivated({param($sender,$event)if($sender.Tag-ne 'immediate' -and $sender.Tag-ne 'opening'){$sender.Close()}})
  $panel.Add_Closed({param($sender,$event)if([Object]::ReferenceEquals($sender,$script:quotaCard)){$script:quotaCard=$null}})
  Update-QuotaCapsule
  # Place near the pet using the native screen's work area and widget DPI.
  try{
    $screenPoint=$script:window.PointToScreen([Windows.Point]::new(0,0))
    $source=[Windows.PresentationSource]::FromVisual($script:window)
    $transform=$source.CompositionTarget.TransformFromDevice
    $screen=[Windows.Forms.Screen]::FromPoint([Drawing.Point]::new([int]$screenPoint.X,[int]$screenPoint.Y)).WorkingArea
    $lo=$transform.Transform([Windows.Point]::new($screen.Left,$screen.Top));$hi=$transform.Transform([Windows.Point]::new($screen.Right,$screen.Bottom));$anchor=$transform.Transform($screenPoint)
    $panel.Left=[Math]::Max($lo.X+8,[Math]::Min($hi.X-$panel.Width-8,$anchor.X-$panel.Width+90))
    $panel.Top=[Math]::Max($lo.Y+8,[Math]::Min($hi.Y-$panel.Height-8,$anchor.Y))
  }catch{$panel.WindowStartupLocation='CenterScreen'}
  Add-QuotaTransition $panel
  $panel.Show()
  Update-QuotaCapsule
}
