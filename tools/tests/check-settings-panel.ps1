$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
$script:appDir=Join-Path $root 'sakura-studio/quota-pet'
$script:dataDir=Join-Path $root 'reports/settings-fixture';$null=New-Item -ItemType Directory -Force $script:dataDir
. (Join-Path $script:appDir 'runtime/quota-card.ps1')
. (Join-Path $script:appDir 'runtime/settings-panel.ps1')
function Save-Settings {$script:saves++}
function Set-Appearance {}
function Update-IdleSprite {}
$script:idleAnimationOn=$true
function Update-WidgetSettingsMenu {}
function Update-QuotaNotice {}
function Tick-Widget {}
function Set-WidgetAudioVolume {}
function Stop-WidgetAudio {}
function Set-WidgetColorMode($Mode){$script:colorMode=$Mode}
function Get-ActivitySnapshot {return $null}
function Request-Refresh {$script:refreshes++}
function Open-TokenPanel {$script:reports++}
function Pump([int]$Ms){
 $frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds($Ms)
 $timer.Tag=$frame;$timer.Add_Tick({param($sender,$event)$sender.Stop();$sender.Tag.Continue=$false});$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
}
$script:window=[Windows.Markup.XamlReader]::Parse('<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Width="250" Height="120" Left="20" Top="20" ShowActivated="False"><Button Name="Capsule" Width="196" Height="48"/></Window>')
$script:ui=@{QuotaCapsule=$script:window.FindName('Capsule')}
$script:window.Show();Pump 50
$script:config=@{codexPath='missing'}
$script:status=@{ok=$false;queryOk=$false}
$script:desktopTopmost=$false;$script:followHost=$false;$script:fullscreenYieldOn=$true;$script:quotaAlertsOn=$true;$script:quotaAlertThreshold=20
$script:announcementsOn=$true;$script:scale=1.0;$script:soundVolume=0.9;$script:soundOn=$false;$script:colorMode='original';$script:colorPaused=$false
$script:shortcuts=@(@{label='日报';action='report';url=''},@{label='刷新';action='refresh';url=''},@{label='设置';action='settings';url=''})
foreach($url in @('javascript:alert(1)','file:///tmp/a','https://user:pass@example.org','http://example.org','https://example.org/a b','https://example.org\bad')){if(Test-WidgetWebLink $url){throw ('Unsafe link accepted: '+$url)}}
if(!(Test-WidgetWebLink 'https://example.org/a?q=1')){throw 'HTTPS link rejected'}
$script:lastShortcutOpen=0;$script:opens=0
if(!(Open-WidgetWebLink 'https://example.org' {$script:opens++})){throw 'Explicit open failed'}
Open-WidgetWebLink 'https://example.org' {$script:opens++}|Out-Null
if($script:opens-ne 1){throw 'Duplicate open not throttled'}
$clean=@(ConvertTo-WidgetShortcuts @(@{label='bad';action='url';url='javascript:x'},@{label='good';action='report'}))
if($clean.Count-ne 1){throw 'Invalid shortcut persisted'}
Open-WidgetSettingsPanel
Pump 80
if($script:settingsPanel.Resources['MorphFromWidth']-gt 250){throw 'Opening did not originate from capsule width'}
Pump 350
if([Math]::Abs($script:settingsPanel.Width-510)-gt 1 -or $script:settingsPanel.Tag-ne 'ready'){throw 'Morph target not reached'}
$panel=$script:settingsPanel
if($script:shortcutEditors.Count-ne 3){throw 'Shortcut editors missing'}
if($panel.FindName('SettingsDiagnostics').Text-notlike '*未找到*'){throw 'Read-only diagnostics missing'}
$script:shortcutEditors[0].Action.SelectedIndex=5;$script:shortcutEditors[0].Url.Text='file:///bad'
Save-UnifiedWidgetSettings
if($script:saves){throw 'Invalid input partially saved'}
$script:shortcutEditors[0].Url.Text='https://example.org';$script:shortcutEditors[0].Label.Text='资料'
$panel.FindName('SettingsAnnouncements').IsChecked=$false
Save-UnifiedWidgetSettings
if($script:saves-ne 1 -or $script:announcementsOn -or $script:shortcuts[0].action-ne 'url'){throw 'Unified settings not saved'}
if($script:opens-ne 1){throw 'Saving launched a website'}
$panel.Measure([Windows.Size]::new(510,640));$panel.Arrange([Windows.Rect]::new(0,0,510,640));$panel.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(510,640,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($panel.Content)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $root 'reports/settings-panel-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
$panel.Close();Pump 70
if($panel.Resources['MorphToWidth']-gt 250){throw 'Closing did not target capsule width'}
Pump 250
if($script:settingsPanel -or $script:shortcutEditors.Count -or $script:ui.QuotaCapsule.Opacity-ne 1){throw 'Panel references or capsule retained'}
for($i=0;$i-lt 12;$i++){Open-WidgetSettingsPanel;$script:settingsPanel.Tag='immediate';$script:settingsPanel.Close()}
$script:window.Close()
'Settings/morph checks passed: real dispatcher animation, reverse collapse, cleanup, validation, no launch on save, explicit-link throttle, read-only diagnostics, 12 reopen cycles'
