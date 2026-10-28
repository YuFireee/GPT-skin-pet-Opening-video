param([string]$Mode='full')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Join-Path $root 'sakura-studio/quota-pet'
$script:dataDir=Join-Path $root ('reports/quota-loop-fixture-'+$Mode);$null=New-Item -ItemType Directory -Force $script:dataDir
. (Join-Path $script:appDir 'runtime/quota-card.ps1')
. (Join-Path $script:appDir 'runtime/quota-notice.ps1')
$script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'widget.xaml')))
$script:ui=@{}
$script:window.FindName('Root')|Out-Null
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $script:appDir 'widget.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in @('Reset-Label','Format-ResetTime','Format-ResetDisplay','Get-QuotaWindowLabel','Get-QuotaRows','Update-Quota')){
 $fn=$ast.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name-eq $name},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
}
foreach($n in @('QuotaNotice','QuotaNoticeText','QuotaCapsule','CapsuleRing','CapsuleValue','CapsuleWeekRing','CapsuleWeekValue','ShortQuotaButton','WeekQuotaButton','Root','Bubble','Tail','TailNear','SceneText','QuotaText','QuoteText','BubbleShape','Girl','PressScale','FacingScale','TextFacingScale','Header','Refresh','MenuButton','Status','LiveDot','ShortRow','WeekRow','ShortLabel','WeekLabel','ShortUsed','ShortLeft','WeekUsed','WeekLeft','ShortReset','WeekReset','ShortBar','WeekBar')){$script:ui[$n]=$script:window.FindName($n)}
function Update-BubbleTooltip {}
function Write-WidgetJson {}
$script:quotaAlertsOn=$false;$script:fullscreenYielded=$false;$script:resetTimeMode='countdown'
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
@{ok=$true;queryOk=$true;observedAt=$now;checkedAt=$now;windows=@(@{minutes=300;used=3;remaining=97;resetsAt=([Math]::Floor($now/1000)+14000)},@{minutes=10080;used=2;remaining=98;resetsAt=([Math]::Floor($now/1000)+500000)})}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $script:dataDir 'status.json') -Encoding UTF8
if($Mode-eq 'legacy'){
 $tok=$null;$err=$null;$legacy=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'github-upload/sakura-studio/quota-pet/widget.ps1'),[ref]$tok,[ref]$err)
 $fn=$legacy.Find({param($a)$a -is [Management.Automation.Language.FunctionDefinitionAst] -and $a.Name-eq 'Get-QuotaRows'},$true)
 . ([scriptblock]::Create($fn.Extent.Text))
}
if($Mode-eq 'no-capsule'){function Update-QuotaCapsule {}}
if($Mode-eq 'no-notice'){function Update-QuotaNotice {}}
if($Mode-eq 'local-only'){function Update-QuotaCapsule {$foo=1}}
if($Mode-eq 'only-parse'){function Update-QuotaCapsule {$value=0.0;[double]::TryParse('97',[ref]$value)|Out-Null}}
if($Mode-eq 'only-tooltip'){function Update-QuotaCapsule {$script:ui.QuotaCapsule.ToolTip=$script:ui.Status.Text+' · 点击展开额度卡片'}}
if($Mode-eq 'only-value'){function Update-QuotaCapsule {$script:ui.CapsuleValue.Text=$script:ui.ShortLeft.Text}}
if($Mode-eq 'rows-only'){function Update-Quota {Get-QuotaRows|Out-Null}}
Write-Output ('MODE='+$Mode+' BODY='+(Get-Command Update-QuotaCapsule).ScriptBlock.ToString().Substring(0,[Math]::Min(100,(Get-Command Update-QuotaCapsule).ScriptBlock.ToString().Length)))
$rows=@()
for($batch=0;$batch-lt 6;$batch++){
 for($i=0;$i-lt 250;$i++){Update-Quota}
 [GC]::Collect();[GC]::WaitForPendingFinalizers();[GC]::Collect()
 $p=[Diagnostics.Process]::GetCurrentProcess();$rows+=@{batch=$batch;managedMB=[Math]::Round([GC]::GetTotalMemory($true)/1MB,1);privateMB=[Math]::Round($p.PrivateMemorySize64/1MB,1);errors=$Error.Count;typeNameChars=(@($script:status.windows)[0].PSObject.TypeNames -join '').Length};$p.Dispose()
}
$rows|ConvertTo-Json|Set-Content (Join-Path $root ('reports/quota-loop-profile-'+$Mode+'.json'))
$rows|ConvertTo-Json -Compress
$script:window.Close()
