function Initialize-WidgetUpdater {$script:autoUpdate=$false;$script:updateProcess=$null}
function Tick-WidgetUpdater([long]$Now) {}
function Start-WidgetUpdate([string]$Mode='manual') {[Windows.MessageBox]::Show('此为樱色主题整合版，请通过樱色工坊更新，避免覆盖角色素材。')|Out-Null}
function Set-WidgetAutomaticUpdate([bool]$Enabled) {$script:autoUpdate=$false;Update-WidgetUpdateMenu}
function Update-WidgetUpdateMenu {if($script:settingsMenuUi.UpdateVersion){$script:settingsMenuUi.UpdateVersion.Header='樱色版 · GPT-Niang 1.3.4';$script:settingsMenuUi.AutoUpdate.IsChecked=$false;$script:settingsMenuUi.AutoUpdate.IsEnabled=$false}}
