$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:appDir=Join-Path $root 'sakura-studio/quota-pet'
$xaml=[IO.File]::ReadAllText((Join-Path $script:appDir 'widget.xaml'))
$script:window=[Windows.Markup.XamlReader]::Parse($xaml);$script:ui=@{}
foreach($match in [regex]::Matches($xaml,'x:Name="([^"]+)"')){$name=$match.Groups[1].Value;$script:ui[$name]=$script:window.FindName($name)}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $script:appDir 'widget.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Widget parse failed'}
foreach($name in @('Click-Character','Show-Quota','Hide-Quota','Switch-Scene','Set-BubbleState','Set-Facing','Set-AnimatedValue','Apply-Scene')){
 $fn=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name-eq $name},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
}
. (Join-Path $script:appDir 'runtime/quota-card.ps1')
function Set-WidgetSceneLayout {}
function Update-BubbleTooltip {}
function Update-QuotaNotice {}
function Restart-SceneTtl {}
function Save-Settings {}
function Request-Refresh {$script:refreshes++}
function Fit-QuoteText {}
function Get-WidgetBubbleQuote($dir){$script:quotes++;return '娴嬭瘯鍙拌瘝 '+$script:quotes}
function Animate-Value($target,$property,[double]$to,[int]$duration,[int]$delay=0){Set-AnimatedValue $target $property $to}
function Open-QuotaCard {$script:cardOpens++}
$script:collapsed=$true;$script:status=@{windows=@(@{minutes=300;remaining=26},@{minutes=10080;remaining=73})}
$script:ui.Girl.Source=[Windows.Media.Imaging.BitmapImage]::new([Uri](Join-Path $script:appDir 'assets/confirmation-soft/frames/000.png'))
$script:window.Show();$script:window.Measure([Windows.Size]::new(350,350));$script:window.Arrange([Windows.Rect]::new(0,0,350,350));$script:window.UpdateLayout()
Set-BubbleState;Update-QuotaCapsule
foreach($side in @('right','left')){
 $script:side=$side;Set-Facing;$script:window.UpdateLayout()
 $a=$script:ui.QuotaCapsule.TranslatePoint([Windows.Point]::new(46,20),$script:ui.Root)
 $b=$script:ui.Girl.TranslatePoint([Windows.Point]::new(104,0),$script:ui.Root)
 if([Math]::Abs($a.X-$b.X)-gt .01){throw 'Rings not centered over character'}
 $short=$script:ui.ShortQuotaButton.TranslatePoint([Windows.Point]::new(20,20),$script:window)
 $week=$script:ui.WeekQuotaButton.TranslatePoint([Windows.Point]::new(20,20),$script:window)
 if($short.X-ge $week.X){throw 'Mirroring reversed the quota order'}
}
$script:side='right';Set-Facing
if($script:ui.CapsuleValue.Text-ne '26%' -or $script:ui.CapsuleWeekValue.Text-ne '73%'){throw 'Ring values reversed'}
$binding=$ast.Find({param($a)$a -is [Management.Automation.Language.ForEachStatementAst] -and $a.Extent.Text.StartsWith('foreach($quotaButton in')},$true)
. ([scriptblock]::Create($binding.Extent.Text))
foreach($button in @($script:ui.ShortQuotaButton,$script:ui.WeekQuotaButton)){$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
if($script:cardOpens-ne 2){throw 'Quota circles do not open the card'}
Click-Character
if($script:ui.QuotaCapsule.Visibility-ne 'Collapsed'){throw 'Quota circles overlap the quote bubble'}
if($script:cardOpens-ne 2 -or $script:bubbleMode-ne 'quote' -or $script:ui.QuoteText.Visibility-ne 'Visible' -or $script:refreshes){throw 'Character click opened quota or refreshed instead of quoting'}
Click-Character
if($script:quotes-ne 2 -or $script:bubbleMode-ne 'quote'){throw 'Repeated character click did not advance quote'}
if($script:sceneTimer){$script:sceneTimer.Stop()}
Hide-Quota
if($script:ui.QuotaCapsule.Visibility-ne 'Collapsed'){throw 'Rings restored before bubble finished closing'}
$frame=[Windows.Threading.DispatcherFrame]::new();$timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(620);$timer.Tag=$frame;$timer.Add_Tick({param($sender,$event)$sender.Stop();$sender.Tag.Continue=$false});$timer.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
if($script:ui.QuotaCapsule.Visibility-ne 'Visible'){throw 'Rings not restored after bubble closed'}
Set-BubbleState
foreach($n in @('Bubble','Tail','TailNear')){$script:ui[$n].Visibility='Hidden'}
$stage=$script:window.FindName('AnimationStage');$stage.Measure([Windows.Size]::new(378,378));$stage.Arrange([Windows.Rect]::new(0,0,378,378));$stage.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(378,378,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($stage)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $root 'reports/pet-double-rings-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
$script:window.Close()
'Pet interaction checks passed: centered dual rings, left/right orientation, independent clicks, quote-only character clicks, no refresh on quote.'
