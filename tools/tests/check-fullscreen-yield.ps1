$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'sakura-studio/quota-pet/runtime/fullscreen-yield.ps1')
$monitor=[SakuraFullscreen+Rect]::new(0,0,1920,1080)
if(![SakuraFullscreen]::Covers($true,$false,$false,$true,$false,$monitor,$monitor)){throw 'Fullscreen rejected'}
if([SakuraFullscreen]::Covers($true,$false,$true,$true,$false,$monitor,$monitor)){throw 'Maximized window accepted'}
if([SakuraFullscreen]::Covers($true,$false,$false,$false,$false,$monitor,$monitor)){throw 'Other monitor accepted'}
if([SakuraFullscreen]::Covers($true,$false,$false,$true,$true,$monitor,$monitor)){throw 'Own window accepted'}
$small=[SakuraFullscreen+Rect]::new(0,0,1920,1040)
if([SakuraFullscreen]::Covers($true,$false,$false,$true,$false,$small,$monitor)){throw 'Work-area window accepted'}
$negative=[SakuraFullscreen+Rect]::new(-1920,0,0,1080)
if(![SakuraFullscreen]::Covers($true,$false,$false,$true,$false,$negative,$negative)){throw 'Negative monitor coordinates rejected'}
Add-Type 'public static class GptWidgetNative {public static int Calls;public static bool SetWindowPos(System.IntPtr h,System.IntPtr a,int x,int y,int w,int z,uint f){Calls++;return true;}}'
function Close-QuotaCard {param([switch]$Immediate)$script:cardClosed++}
function Hide-Quota {$script:collapsed=$true}
$script:fullscreenYieldOn=$true;$script:fullscreenYielded=$false;$script:fullscreenCandidate=$false;$script:fullscreenCheckedAt=0;$script:fullscreenCandidateSince=0;$script:desktopTopmost=$true;$script:collapsed=$false;$script:widgetHandle=[IntPtr]1
Update-WidgetFullscreen 1000 {$true};if($script:fullscreenYielded){throw 'Enter debounce missing'}
Update-WidgetFullscreen 2000 {$true};if(!$script:fullscreenYielded -or !$script:collapsed -or $script:cardClosed-ne 1){throw 'Enter behavior failed'}
Update-WidgetFullscreen 2100 {throw 'Rate limit must skip this probe'}
Update-WidgetFullscreen 3000 {$false};if(!$script:fullscreenYielded){throw 'Exit debounce missing'}
Update-WidgetFullscreen 4000 {$false};if($script:fullscreenYielded -or [GptWidgetNative]::Calls-ne 1){throw 'Restore behavior failed'}
if(!$script:desktopTopmost){throw 'Saved topmost preference changed'}
$script:fullscreenYieldOn=$false;Update-WidgetFullscreen 5000 {throw 'Disabled detector called'}
'Fullscreen checks passed: full geometry, maximized/own/other-monitor exclusions, negative monitor, debounce, rate limit, collapse and preference preservation'

foreach($name in @('ScreenClippingHost','SnippingTool','Snipaste','QQScreenshot','ShareX')){
 if(![SakuraFullscreen]::TransientName($name)){throw ('Screenshot tool not excluded: '+$name)}
}
if([SakuraFullscreen]::TransientName('msedge')){throw 'Browser incorrectly ignored'}
$widgetSource=[IO.File]::ReadAllText((Join-Path $root 'sakura-studio/quota-pet/widget.ps1'))
if($widgetSource -notmatch '\$visible=\$visible[^\r\n]+-and !\$script:fullscreenYielded'){throw 'Fullscreen must really hide the pet'}
'Fullscreen regression checks passed: screenshot exclusions and real visibility gate'
