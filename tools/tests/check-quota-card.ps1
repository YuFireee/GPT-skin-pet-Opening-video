$ErrorActionPreference='Stop'

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing

$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$null=New-Item -ItemType Directory -Path (Join-Path $root 'reports') -Force

$script:appDir=Join-Path $root 'sakura-studio/quota-pet'

. (Join-Path $script:appDir 'runtime/quota-card.ps1')

. (Join-Path $script:appDir 'runtime/settings-panel.ps1')

$script:announcementsOn=$true;$script:dataDir=Join-Path $root 'reports/quota-fixture'

$script:shortcuts=@(@{label='日报';action='report';url=''},@{label='刷新';action='refresh';url=''},@{label='设置';action='settings';url=''})

$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'widget.xaml')))

$script:ui=@{}

foreach($name in @('QuotaCapsule','CapsuleRing','CapsuleValue','CapsuleWeekRing','CapsuleWeekValue','ShortQuotaButton','WeekQuotaButton','ShortLeft','WeekLeft','ShortLabel','WeekLabel','ShortReset','WeekReset','Status')){$script:ui[$name]=$script:window.FindName($name)}

$script:ui.ShortLeft.Text='85%';$script:ui.WeekLeft.Text='62%';$script:ui.ShortLabel.Text='5 小时';$script:ui.WeekLabel.Text='每周';$script:ui.ShortReset.Text='本机时间 15:00 重置';$script:ui.WeekReset.Text='周日重置';$script:ui.Status.Text='10:00 更新'

$script:status=@{planLabel='测试套餐';windows=@(@{minutes=300;remaining=85},@{minutes=10080;remaining=62})};$script:collapsed=$true;$script:desktopTopmost=$false

function Get-ActivitySnapshot {return ('{"days":{"2026-10-23":12340},"recentMinutes":{"123/model":500}}'|ConvertFrom-Json)}

function Request-Refresh {$script:refreshes++}

function Open-TokenPanel {$script:reports++}

Update-QuotaCapsule

if($script:ui.CapsuleValue.Text-ne '85%'){throw 'Capsule value mismatch'}

Open-QuotaCard

if($script:quotaCard.FindName('CardShortcuts').Children.Count-ne 3){throw 'Configurable shortcuts missing'}

if($script:quotaCard.FindName('CardShortValue').Text-ne '85%'){throw 'Card value mismatch'}

if($script:quotaCard.FindName('CardSevenTokens').Text -notlike '*12*340*'){throw 'Token summary mismatch'}

$card=$script:quotaCard;$card.BeginAnimation([Windows.UIElement]::OpacityProperty,$null);$card.Opacity=1

$card.Measure([Windows.Size]::new(350,596));$card.Arrange([Windows.Rect]::new(0,0,350,596));$card.UpdateLayout()

$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(350,596,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($card.Content)

$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $root 'reports/quota-card-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}

$card.FindName('RefreshCard').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));if($script:refreshes-ne 1){throw 'Refresh event mismatch'}

$card.FindName('OpenReport').RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent));if($script:reports-ne 1 -or $script:quotaCard){throw 'Report handoff mismatch'}

for($i=0;$i-lt 15;$i++){Open-QuotaCard;Close-QuotaCard -Immediate};if($script:quotaCard){throw 'Card retained after closing'}

$script:ui.ShortLeft.Text='—';$script:status.windows=@(@{minutes=10080;remaining=62});Update-QuotaCapsule;if($script:ui.CapsuleValue.Text-ne '—'){throw 'Unknown quota must remain unknown'}

if($script:ui.CapsuleWeekValue.Text-ne '62%'){throw 'Missing short quota changed weekly ring'}
$script:status.windows=@(@{kind='individual';minutes=300;remaining=99},@{minutes=60;remaining=90});Update-QuotaCapsule
if($script:ui.CapsuleValue.Text-ne '—' -or $script:ui.CapsuleWeekValue.Text-ne '—'){throw 'Other quota windows substituted into fixed rings'}
$script:status.windows=@(@{minutes=300;remaining=20;resetsAt=1},@{minutes=10080;remaining=0});Update-QuotaCapsule
if($script:ui.CapsuleValue.Text-ne '—' -or $script:ui.CapsuleWeekValue.Text-ne '0%'){throw 'Expired and zero quota confused'}
$script:window.Close()

'Quota capsule/card tests passed: real values, unknown quota, token summary, refresh, report handoff, 15 open/close cycles'

