function Get-ActivitySnapshot {
  try {return (Get-Content -LiteralPath (Join-Path $script:dataDir 'activity.json') -Raw -Encoding UTF8|ConvertFrom-Json)}catch{return $null}
}
function Open-TokenPanel {
  if($script:activityPanel -and $script:activityPanel.IsVisible){$script:activityPanel.Activate()|Out-Null;return}
  $panel=New-Object Windows.Window;$panel.Title='樱色工坊 · 日报';$panel.Width=520;$panel.Height=650;$panel.WindowStyle='None';$panel.ResizeMode='NoResize';$panel.AllowsTransparency=$true;$panel.Background=[Windows.Media.Brushes]::Transparent;$panel.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#51445F');$panel.FontFamily='Microsoft YaHei UI';$panel.FontSize=13;$panel.WindowStartupLocation='CenterScreen';$panel.ShowInTaskbar=$false;if($script:window -and $script:window.IsVisible){$panel.Owner=$script:window};$panel.Topmost=[bool]$script:desktopTopmost
  $panel.MaxHeight=[Math]::Max(350,[Windows.SystemParameters]::WorkArea.Height-20)
  $resources=[Windows.Markup.XamlReader]::Parse(@'
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">
 <Style TargetType="Button"><Setter Property="Padding" Value="12,7"/><Setter Property="Margin" Value="0,4"/><Setter Property="Foreground" Value="#60465F"/><Setter Property="Background" Value="#EFE2EF"/><Setter Property="BorderThickness" Value="0"/><Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button"><Border Background="{TemplateBinding Background}" CornerRadius="9" Padding="{TemplateBinding Padding}"><ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/></Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#E3D0E4"/></Trigger></ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter></Style>
 <Style TargetType="ComboBox"><Setter Property="Padding" Value="8,5"/><Setter Property="Margin" Value="0,4"/><Setter Property="Background" Value="#F7EFF7"/></Style>
</ResourceDictionary>
'@)
  $panel.Resources.MergedDictionaries.Add($resources)
  $frame=New-Object Windows.Controls.Border;$frame.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#FCF9FF');$frame.BorderBrush=[Windows.Media.BrushConverter]::new().ConvertFromString('#E1D6E9');$frame.BorderThickness='1';$frame.CornerRadius='20';$frame.Padding='20';$panel.Content=$frame
  $scroll=New-Object Windows.Controls.ScrollViewer;$scroll.VerticalScrollBarVisibility='Auto';$stack=New-Object Windows.Controls.StackPanel;$scroll.Content=$stack;$frame.Child=$scroll
  $header=New-Object Windows.Controls.Grid;$header.Margin='0,0,0,10'
  $title=New-Object Windows.Controls.TextBlock;$title.Text='用量日报';$title.FontSize=22;$title.FontWeight='SemiBold';$title.VerticalAlignment='Center';$header.Children.Add($title)|Out-Null
  $close=New-Object Windows.Controls.Button;$close.Content='×';$close.Width=30;$close.Height=30;$close.Padding='0';$close.HorizontalAlignment='Right';$close.Add_Click({$script:activityPanel.Close()});$header.Children.Add($close)|Out-Null;$stack.Children.Add($header)|Out-Null
  $header.Add_MouseLeftButtonDown({param($sender,$event)if($event.ClickCount-eq 1){try{$script:activityPanel.DragMove()}catch{}}})
  $tabs=New-Object Windows.Controls.StackPanel;$tabs.Orientation='Horizontal';$tabs.Margin='0,0,0,8'
  $script:tokenOverviewTab=New-Object Windows.Controls.Button;$script:tokenOverviewTab.Content='概览';$script:tokenOverviewTab.Margin='0,0,8,0';$script:tokenOverviewTab.Add_Click({Set-TokenReportTab 'overview'});$tabs.Children.Add($script:tokenOverviewTab)|Out-Null
  $script:tokenModelsTab=New-Object Windows.Controls.Button;$script:tokenModelsTab.Content='模型';$script:tokenModelsTab.Add_Click({Set-TokenReportTab 'models'});$tabs.Children.Add($script:tokenModelsTab)|Out-Null;$stack.Children.Add($tabs)|Out-Null
  $data=Get-ActivitySnapshot
  $text=New-Object Windows.Controls.TextBlock;$text.TextWrapping='Wrap';$text.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#8B738C');$text.Text='仅保留近7天与约5小时。本机日志统计，不代表账户完整账单。';$stack.Children.Add($text)|Out-Null
  if($data){Add-TokenCharts $stack $data}else{$notice=New-Object Windows.Controls.TextBlock;$notice.Text='正在读取本机用量，请稍后重新打开。';$notice.Margin='0,16,0,0';$stack.Children.Add($notice)|Out-Null}
  $panel.Add_Closed({param($sender,$event)if([Object]::ReferenceEquals($sender,$script:activityPanel)){$script:activityPanel=$null;$script:tokenChartHost=$null;$script:tokenModel=$null;$script:tokenRange=$null;$script:tokenChartData=$null;$script:tokenRangeButtons=@();$script:tokenOverviewTab=$null;$script:tokenModelsTab=$null;$script:tokenBucketSource=$null;$script:tokenDailyCache=@{};$script:tokenHourlyCache=@{}}})
  if($script:tokenModel){Set-TokenReportTab 'overview'};$script:activityPanel=$panel;if(Get-Command Add-QuotaTransition -ErrorAction SilentlyContinue){Add-QuotaTransition $panel};$panel.Add_KeyDown({param($sender,$event)if($event.Key-eq 'Escape'){$sender.Close();$event.Handled=$true}});$panel.Show()
}
