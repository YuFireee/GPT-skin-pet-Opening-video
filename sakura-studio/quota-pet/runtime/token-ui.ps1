function Get-TokenBucketValue($Buckets,[string]$Day,[int]$Hour=-1,[string]$Model='全部模型'){
  if(![Object]::ReferenceEquals($Buckets,$script:tokenBucketSource) -or $Model-ne $script:tokenBucketModel){
    $script:tokenBucketSource=$Buckets;$script:tokenBucketModel=$Model;$script:tokenDailyCache=@{};$script:tokenHourlyCache=@{}
    foreach($entry in $Buckets.PSObject.Properties){$parts=$entry.Name -split '/',3;if($parts.Count-ne 3){continue};if($Model-ne '全部模型' -and $parts[2]-ne $Model){continue};$hourKey=$parts[0]+'/'+$parts[1];$script:tokenDailyCache[$parts[0]]+=[double]$entry.Value;$script:tokenHourlyCache[$hourKey]+=[double]$entry.Value}
  }
  if($Hour-ge 0){return [double]$script:tokenHourlyCache[$Day+'/'+$Hour.ToString('00')]}
  return [double]$script:tokenDailyCache[$Day]

}
function Update-TokenChart {
  $data=$script:tokenChartData;$chartPanel=$script:tokenChartHost
  if(!$chartPanel -or !$data -or $script:tokenModelUpdating){return};$chartPanel.Children.Clear()
  $model=[string]$script:tokenModel.SelectedItem;$mode=[string]$script:tokenRange.SelectedItem
  foreach($button in $script:tokenRangeButtons){$button.FontWeight=if($button.Tag-eq $mode){'SemiBold'}else{'Normal'}}
  $now=[DateTimeOffset]::FromUnixTimeMilliseconds([long]$data.checkedAt).LocalDateTime.Date
  $today=Get-TokenBucketValue $data.buckets ($now.ToString('yyyy-MM-dd')) -Model $model
  $yesterday=Get-TokenBucketValue $data.buckets ($now.AddDays(-1).ToString('yyyy-MM-dd')) -Model $model
  $summary=New-Object Windows.Controls.Grid;$summary.Margin='0,8,0,12'
  $summary.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new());$summary.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new());$summary.RowDefinitions.Add([Windows.Controls.RowDefinition]::new());$summary.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
  $all=($script:tokenDailyCache.Values|Measure-Object -Sum).Sum;$five=0.0
  foreach($entry in $data.recentMinutes.PSObject.Properties){$parts=$entry.Name -split '/',2;if($model-eq '全部模型' -or $parts[1]-eq $model){$five+=[double]$entry.Value}}
  $metrics=@(@{label='近7天 · 已记录';value=[double]$all},@{label='约5小时 · 已记录';value=$five},@{label='今日';value=$today},@{label='昨日';value=$yesterday})
  for($i=0;$i-lt 4;$i++){
    $tile=New-Object Windows.Controls.Border;$tile.CornerRadius='11';$tile.Padding='12,9';$tile.Margin='3';$tile.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#F0EAF6');$column=New-Object Windows.Controls.StackPanel
    $caption=New-Object Windows.Controls.TextBlock;$caption.Text=$metrics[$i].label;$caption.FontSize=11;$caption.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#9983A3');$column.Children.Add($caption)|Out-Null
    $number=New-Object Windows.Controls.TextBlock;$number.FontSize=21;$number.Text=$metrics[$i].value.ToString('N0');$number.ToolTip=$number.Text+' Token';$column.Children.Add($number)|Out-Null;$tile.Child=$column;[Windows.Controls.Grid]::SetRow($tile,[int][Math]::Floor($i/2));[Windows.Controls.Grid]::SetColumn($tile,$i%2);$summary.Children.Add($tile)|Out-Null
  }
  $chartPanel.Children.Add($summary)|Out-Null
  $items=@()
  if($mode-eq '近5小时'){
    $end=[Math]::Floor([double]$data.checkedAt/60000)+1;$start=$end-300
    $values=New-Object double[] 30
    foreach($entry in $data.recentMinutes.PSObject.Properties){$parts=$entry.Name -split '/',2;if($parts.Count-ne 2){continue};if($model-ne '全部模型' -and $parts[1]-ne $model){continue};$index=[int][Math]::Floor(([double]$parts[0]-$start)/10);if($index-ge 0 -and $index-lt 30){$values[$index]+=[double]$entry.Value}}
    for($i=0;$i-lt 30;$i++){$label=[DateTimeOffset]::FromUnixTimeSeconds([long](($start+$i*10)*60)).ToLocalTime().ToString('HH:mm');$items+=@{label=$label;value=$values[$i]}}
  }else{
    for($i=6;$i-ge 0;$i--){$day=$now.AddDays(-$i);$items+=@{label=$day.ToString('MM-dd');value=(Get-TokenBucketValue $data.buckets ($day.ToString('yyyy-MM-dd')) -Model $model)}}
  }
  $maximum=[Math]::Max(1,($items|ForEach-Object {$_.value}|Measure-Object -Maximum).Maximum)
  $canvas=New-Object Windows.Controls.Canvas;$canvas.Width=440;$canvas.Height=180;$canvas.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#F5F0F9')
  $step=440.0/$items.Count
  for($i=0;$i-lt $items.Count;$i++){
    $height=140*$items[$i].value/$maximum
    $bar=New-Object Windows.Shapes.Rectangle;$bar.Width=[Math]::Max(2,$step-4);$bar.Height=[Math]::Max(1,$height);$bar.RadiusX=2;$bar.RadiusY=2;$bar.Fill=[Windows.Media.BrushConverter]::new().ConvertFromString('#B57CA6');$bar.ToolTip=$items[$i].label+' · '+$items[$i].value.ToString('N0')+' Token'
    [Windows.Controls.Canvas]::SetLeft($bar,$i*$step+2);[Windows.Controls.Canvas]::SetTop($bar,145-$height);$canvas.Children.Add($bar)|Out-Null
    if($i%[Math]::Max(1,[int][Math]::Ceiling($items.Count/7))-eq 0){$label=New-Object Windows.Controls.TextBlock;$label.Text=$items[$i].label;$label.FontSize=10;[Windows.Controls.Canvas]::SetLeft($label,$i*$step);[Windows.Controls.Canvas]::SetTop($label,153);$canvas.Children.Add($label)|Out-Null}
  }
  $chartPanel.Children.Add($canvas)|Out-Null
  $total=($items|ForEach-Object {$_.value}|Measure-Object -Sum).Sum
  $footer=New-Object Windows.Controls.TextBlock;$footer.Text="本视图已读取合计：$($total.ToString('N0')) Token。含缓存输入，不代表费用。";if($data.bucketLimited){$footer.Text+=' 部分日志的分组数量达到上限，小时与模型统计不完整。'};if($data.tailLimited){$footer.Text+=' 首次仅读取日志末尾，历史可能不全；不会把此前累计量算作本次消耗。'};if($data.checkedAt){$footer.Text+=' 更新于 '+[DateTimeOffset]::FromUnixTimeMilliseconds([long]$data.checkedAt).ToLocalTime().ToString('HH:mm:ss')+'。'};if($data.progress -and !$data.progress.complete){$footer.Text+=' 近期记录尚在读取中。'};if($data.progress.errors -or $data.progress.excludedFiles){$footer.Text+=' 失败 '+$data.progress.errors+' 份，超限未纳入 '+$data.progress.excludedFiles+' 份。'};$footer.FontSize=11;$footer.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#9983A3');$footer.TextWrapping='Wrap';$footer.Margin='0,8,0,8';$chartPanel.Children.Add($footer)|Out-Null
}
function Add-TokenCharts($Stack,$Data){
  $script:tokenChartData=$Data

  if(!$Data.buckets){$notice=New-Object Windows.Controls.TextBlock;$notice.Text='小时与模型统计等待新版本日志索引，请稍后重新打开。';$Stack.Children.Add($notice)|Out-Null;return}
  $refresh=New-Object Windows.Controls.Button;$refresh.Content='↻ 刷新快照';$refresh.Add_Click({$new=Get-ActivitySnapshot;if($new){$script:tokenChartData=$new;Sync-TokenModels $new;Update-TokenChart}});$Stack.Children.Add($refresh)|Out-Null
  $script:tokenRange=New-Object Windows.Controls.ComboBox;foreach($name in @('近7天','近5小时')){$script:tokenRange.Items.Add($name)|Out-Null};$script:tokenRange.SelectedIndex=0;$script:tokenRange.Visibility='Collapsed';$Stack.Children.Add($script:tokenRange)|Out-Null
  $ranges=New-Object Windows.Controls.StackPanel;$ranges.Orientation='Horizontal';$ranges.Margin='0,5,0,4';$script:tokenRangeButtons=@()
  foreach($name in @('近7天','近5小时')){$button=New-Object Windows.Controls.Button;$button.Content=$name;$button.Tag=$name;$button.Margin='0,0,8,0';$button.Add_Click({param($sender,$event)$script:tokenRange.SelectedItem=[string]$sender.Tag});$script:tokenRangeButtons+=$button;$ranges.Children.Add($button)|Out-Null};$Stack.Children.Add($ranges)|Out-Null
  $script:tokenModel=New-Object Windows.Controls.ComboBox;$script:tokenModel.Margin='0,6,0,6';$script:tokenModel.Items.Add('全部模型')|Out-Null
  $models=@($Data.buckets.PSObject.Properties|ForEach-Object {($_.Name -split '/',3)[2]}|Sort-Object -Unique);foreach($name in $models){if($name){$script:tokenModel.Items.Add($name)|Out-Null}};$script:tokenModel.SelectedIndex=0;$Stack.Children.Add($script:tokenModel)|Out-Null
  $script:tokenChartHost=New-Object Windows.Controls.StackPanel;$Stack.Children.Add($script:tokenChartHost)|Out-Null
  $script:tokenRange.Add_SelectionChanged({Update-TokenChart});$script:tokenModel.Add_SelectionChanged({Update-TokenChart});Update-TokenChart
}
function Set-TokenReportTab([string]$Tab){
  if(!$script:tokenModel){return}
  $script:tokenModel.Visibility=if($Tab-eq 'models'){[Windows.Visibility]::Visible}else{[Windows.Visibility]::Collapsed}
  if($Tab-eq 'overview'){$script:tokenModel.SelectedIndex=0}
  foreach($button in @($script:tokenOverviewTab,$script:tokenModelsTab)){if($button){$button.FontWeight='Normal';$button.Background=[Windows.Media.Brushes]::Transparent}}
  $active=if($Tab-eq 'models'){$script:tokenModelsTab}else{$script:tokenOverviewTab};if($active){$active.FontWeight='SemiBold';$active.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#EBDFF3')}
  Update-TokenChart
}


function Sync-TokenModels($Data){
  if(!$script:tokenModel){return};$selected=[string]$script:tokenModel.SelectedItem;$script:tokenModelUpdating=$true
  try{$script:tokenModel.Items.Clear();$script:tokenModel.Items.Add('全部模型')|Out-Null;$models=@($Data.buckets.PSObject.Properties|ForEach-Object {($_.Name -split '/',3)[2]}|Sort-Object -Unique);foreach($name in $models){if($name){$script:tokenModel.Items.Add($name)|Out-Null}};if($script:tokenModel.Items.Contains($selected)){$script:tokenModel.SelectedItem=$selected}else{$script:tokenModel.SelectedIndex=0}}finally{$script:tokenModelUpdating=$false}
}
