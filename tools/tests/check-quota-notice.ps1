$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'sakura-studio/quota-pet/runtime/quota-notice.ps1')
$script:dataDir=Join-Path $root 'reports/quota-notice-fixture';$null=New-Item -ItemType Directory -Path $script:dataDir -Force
function Write-WidgetJson($File,$Data){$Data|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $File -Encoding UTF8}
$script:ui=@{QuotaNotice=(New-Object Windows.Controls.Border);QuotaNoticeText=(New-Object Windows.Controls.TextBlock)}
$script:window=@{IsVisible=$true};$script:quotaAlertsOn=$true;$script:fullscreenYielded=$true;$script:status=@{ok=$true;queryOk=$true;accountKey='fixture'}
$script:quotaNoticeLoaded=$true;$script:quotaNoticeSeen=$null;$script:quotaNoticeStamp=0
$now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
Write-WidgetJson (Join-Path $script:dataDir 'quota-alerts.json') @{state=@{accountKey='fixture'};events=@(@{id='test';at=$now;text='低额度测试'})}
Update-QuotaNotice;if($script:ui.QuotaNotice.Visibility-ne 'Collapsed'){throw 'Fullscreen notification not deferred'}
$script:fullscreenYielded=$false;Update-QuotaNotice;if($script:ui.QuotaNotice.Visibility-ne 'Visible'){throw 'Pending notice missing'}
$script:quotaNoticeUntil=0;Update-QuotaNotice;if($script:ui.QuotaNotice.Visibility-ne 'Collapsed'){throw 'Repeated notice redisplayed'}
$script:quotaNoticeSeen=$null;$script:quotaNoticeLoaded=$false;Update-QuotaNotice;if($script:ui.QuotaNotice.Visibility-ne 'Collapsed'){throw 'Restart dedup failed'}
$script:quotaAlertsOn=$false;Update-QuotaNotice;if($script:ui.QuotaNotice.Visibility-ne 'Collapsed'){throw 'Disabled notice visible'}
'Notice UI checks passed: fullscreen defer, one-time display, restart dedup, disabled setting'
