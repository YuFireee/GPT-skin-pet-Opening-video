param([string]$Receipt,[double]$Width=800,[double]$Height=500,[switch]$Hidden,[switch]$CaptureEscape)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$window=New-Object Windows.Window
$window.Title='Sakura fit test';$window.Width=$Width;$window.Height=$Height;$window.Left=100;$window.Top=80;$window.ShowInTaskbar=$false
$grid=New-Object Windows.Controls.Grid;$grid.Background=[Windows.Media.Brushes]::DarkSlateBlue
$text=New-Object Windows.Controls.TextBlock;$text.Text='Window sizing test';$text.Foreground=[Windows.Media.Brushes]::White;$text.FontSize=24;$text.Margin=New-Object Windows.Thickness(30);$grid.Children.Add($text)|Out-Null;$window.Content=$grid
function SaveState([string]$File){$point=$grid.PointToScreen([Windows.Point]::new(0,0));$matrix=[Windows.PresentationSource]::FromVisual($window).CompositionTarget.TransformFromDevice;$position=$matrix.Transform($point);[IO.File]::WriteAllText($File,(@{pid=$PID;handle=([Windows.Interop.WindowInteropHelper]::new($window)).Handle.ToInt64();left=$window.Left;top=$window.Top;width=$window.Width;height=$window.Height;client=@{left=$position.X;top=$position.Y;width=$grid.ActualWidth;height=$grid.ActualHeight}}|ConvertTo-Json -Depth 3 -Compress))}
$window.Add_ContentRendered({SaveState $Receipt;if($Hidden){$window.Hide()}})
if($CaptureEscape){
 $grid.Focusable=$true
 $window.Add_Activated({$null=$grid.Focus();$null=[Windows.Input.Keyboard]::Focus($grid)})
 $window.Add_PreviewKeyDown({param($sender,$event);if($event.Key -eq [Windows.Input.Key]::Escape){[IO.File]::WriteAllText($Receipt+'.esc-down','received')}})
 $window.Add_PreviewKeyUp({param($sender,$event);if($event.Key -eq [Windows.Input.Key]::Escape){[IO.File]::WriteAllText($Receipt+'.esc-up','received')}})
}
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[TimeSpan]::FromMilliseconds(100)
$timer.Add_Tick({if(Test-Path -LiteralPath ($Receipt+'.resize')){Remove-Item -LiteralPath ($Receipt+'.resize');$window.Width=650;$window.Height=600; $window.UpdateLayout();SaveState ($Receipt+'.resized')};if(Test-Path -LiteralPath ($Receipt+'.stop')){SaveState ($Receipt+'.final');$window.Close()}})
$timer.Start();$app=New-Object Windows.Application;$app.Run($window)|Out-Null;$timer.Stop()
