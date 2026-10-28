$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$desktop=[Environment]::GetFolderPath('Desktop')
$shortcutPath=Join-Path $desktop 'GPT · 樱色主题.lnk'
$powershellPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments='-NoProfile -WindowStyle Hidden -File "'+(Join-Path $root 'start.ps1')+'" -Theme'
$shell=New-Object -ComObject WScript.Shell
if(Test-Path -LiteralPath $shortcutPath){
  $existing=$shell.CreateShortcut($shortcutPath)
  if($existing.TargetPath -ne $powershellPath -or $existing.Arguments -ne $arguments){throw '同名快捷方式已存在，未覆盖。请先检查它的目标。'}
  $existing.IconLocation=(Join-Path $root 'assets\launcher.ico')+',0'
  $existing.WorkingDirectory=$root
  $existing.Save()
  Write-Output '主题快捷方式和本地图标已修复。'
  exit
}
$shortcut=$shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath=$powershellPath
$shortcut.Arguments=$arguments
$shortcut.WorkingDirectory=$root
$shortcut.WindowStyle=7
$shortcut.Description='自动启动樱色工坊并加载保存的 GPT 主题'
$shortcut.IconLocation=(Join-Path $root 'assets\launcher.ico')+',0'
$shortcut.Save()
$check=$shell.CreateShortcut($shortcutPath)
if($check.TargetPath -ne $powershellPath -or $check.Arguments -ne $arguments){throw '快捷方式写入核验失败。'}
Write-Output ('已创建：'+$shortcutPath)
