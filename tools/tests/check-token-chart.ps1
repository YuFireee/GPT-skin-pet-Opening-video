$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'sakura-studio/quota-pet/runtime/token-ui.ps1')
$at=[DateTimeOffset]::Now.ToUnixTimeMilliseconds();$day=[DateTime]::Today.ToString('yyyy-MM-dd');$prev=[DateTime]::Today.AddDays(-1).ToString('yyyy-MM-dd')
$buckets=@{};$buckets[$day+'/09/model-a']=100;$buckets[$day+'/10/model-b']=30;$buckets[$prev+'/15/model-a']=70
$minutes=@{};$minutes[([Math]::Floor($at/60000)-2).ToString()+'/model-a']=45
$data=@{recentMinutes=($minutes|ConvertTo-Json|ConvertFrom-Json);checkedAt=$at;buckets=($buckets|ConvertTo-Json|ConvertFrom-Json)}
$stack=New-Object Windows.Controls.StackPanel
Add-TokenCharts $stack $data
if((Get-TokenBucketValue $data.buckets $day)-ne 130){throw 'Today total mismatch'}
if((Get-TokenBucketValue $data.buckets $day -Model 'model-a')-ne 100){throw 'Model filter mismatch'}
foreach($mode in @('近7天','近5小时')){
 $script:tokenRange.SelectedItem=$mode;Update-TokenChart
 $canvas=$script:tokenChartHost.Children[1];$bars=@($canvas.Children|Where-Object {$_ -is [Windows.Shapes.Rectangle]})
 $expected=if($mode-eq '近7天'){7}else{30}
 if($mode-eq '近5小时' -and $script:tokenChartHost.Children[2].Text -notlike '*45*'){throw 'Five-hour sum mismatch'}
 if($bars.Count-ne $expected){throw ('Incorrect bars: '+$mode)}
}
for($i=0;$i-lt 60;$i++){Update-TokenChart};if($script:tokenChartHost.Children.Count-ne 3){throw 'Chart controls accumulating'}
'Native Token chart checks passed: ranges, hourly buckets, model filters, bounded controls'
