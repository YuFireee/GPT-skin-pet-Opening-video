$ErrorActionPreference='Stop'
$taskRoot=Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try{
 & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'prepare.ps1')
 if($LASTEXITCODE){throw 'Native build failed'}
 foreach($taskFile in @(Get-ChildItem -LiteralPath (Join-Path $taskRoot 'sakura-studio') -File -Recurse|Where-Object {$_.Extension -in @('.mjs','.js')})){
  if($taskFile.FullName.Contains('\state\')){continue}
  & node --check $taskFile.FullName
  if($LASTEXITCODE){throw ('Syntax check failed: '+$taskFile.Name)}
 }
 foreach($taskTest in @('check-native-control','check-theme-startup','check-debug-port','check-resource-limits','check-renderer-resources','check-background-stop','check-pet-resources','check-boot-monitor','check-start-order','check-readiness','check-control-center','check-user-bubble','check-escape','check-waiting-loop','check-window-replacement')){
  & node (Join-Path $PSScriptRoot ('tests\'+$taskTest+'.mjs'))
  if($LASTEXITCODE){throw ('Check failed: '+$taskTest)}
 }
 & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'tests/check-native-tcp.ps1')
 if($LASTEXITCODE){throw 'Native TCP ownership check failed.'}
 & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'tests/check-idle-player.ps1') -UsePrecompiled
 if($LASTEXITCODE){throw 'Precompiled pet animation check failed.'}
 & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'tests/check-pet-visibility.ps1')
 if($LASTEXITCODE){throw 'Pet visibility recovery check failed.'}
 & powershell.exe -NoProfile -File (Join-Path $PSScriptRoot 'tests/check-user-materials.ps1')
 if($LASTEXITCODE){throw 'User material generation check failed (complete FFmpeg/FFprobe must be on PATH).'}
 'All project checks passed.'
}finally{Pop-Location}
