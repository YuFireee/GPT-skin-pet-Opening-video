$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'sakura-studio/quota-pet/runtime/token-ui.ps1')
. (Join-Path $root 'sakura-studio/quota-pet/runtime/activity-ui.ps1')
function Get-ActivitySnapshot {return ('{"checkedAt":1792728000000,"buckets":{"2026-10-23/09/model-a":123400,"2026-10-22/10/model-b":65000,"2026-10-21/11/model-a":85000},"recentMinutes":{},"sessions":[{"title":"MUST NOT DISPLAY"}]}'|ConvertFrom-Json)}
Open-TokenPanel
if(!$script:activityPanel.IsVisible){throw 'Panel did not open'}
$stack=$script:activityPanel.Content.Child.Content
if($stack.Children.Count-lt 6){throw 'Token controls missing'}
$labels=@($stack.Children|Where-Object {$_ -is [Windows.Controls.TextBlock]}|ForEach-Object Text)-join ' '
if($labels -like '*MUST NOT DISPLAY*'){throw 'Conversation leaked into token panel'}
Set-TokenReportTab 'models';if($script:tokenModel.Visibility-ne 'Visible'){throw 'Model tab not showing filter'}
Set-TokenReportTab 'overview';if($script:tokenModel.Visibility-ne 'Collapsed'){throw 'Overview filter not collapsed'}
$null=New-Item -ItemType Directory -Path (Join-Path $root 'reports') -Force
$card=$script:activityPanel;$card.Measure([Windows.Size]::new(520,650));$card.Arrange([Windows.Rect]::new(0,0,520,650));$card.UpdateLayout()
$bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new(520,650,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($card.Content)
$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap));$stream=[IO.File]::Create((Join-Path $root 'reports/token-report-preview.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
$script:activityPanel.Close()
'Native Token-only panel opened/closed; no conversation list'
