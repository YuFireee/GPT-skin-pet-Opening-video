param([switch]$Theme,[switch]$Workspace)
try {
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $MyInvocation.MyCommand.Path
$expectedVersion='0.9.6'
$studioUrl='http://127.0.0.1:56895/'
if(!(Test-Path -LiteralPath (Join-Path $root 'assets\sakura-calm-soft-portrait.png')) -or !(Test-Path -LiteralPath (Join-Path $root 'SakuraControl.exe')) -or !(Test-Path -LiteralPath (Join-Path $root 'SakuraBoot.exe'))){throw '此公开源码版未附带主题素材。请先按仓库 materials/README.md 配置本地素材，再运行根目录 prepare.cmd。'}

$hashProvider=[Security.Cryptography.SHA256]::Create()
try{$expectedInstallation=([BitConverter]::ToString($hashProvider.ComputeHash([Text.Encoding]::UTF8.GetBytes($root.ToLowerInvariant())))).Replace('-','').ToLowerInvariant()}finally{$hashProvider.Dispose()}
$node=(Get-Command node -ErrorAction SilentlyContinue).Source
if(!$node){throw '需要 Node.js 22 或更新版本。请先安装后重试。'}
if($Theme){
  try{$launchSettings=Get-Content -LiteralPath (Join-Path $root 'state\settings.json') -Raw | ConvertFrom-Json;if($launchSettings.boot -eq $true){$Workspace=$true}}catch{}
}
function OpenControl {
  $control=Join-Path $root 'SakuraControl.exe'
  if(!(Test-Path -LiteralPath $control -PathType Leaf)){throw '未找到原生控制窗口，请先运行 build-visual.ps1 编译。'}
  $owner=Invoke-RestMethod -Uri ($studioUrl+'health') -TimeoutSec 2
  Start-Process -FilePath $control -ArgumentList @('--show','--parent',[string]$owner.pid) -WorkingDirectory $root -WindowStyle Hidden
}
function OpenStudio {
  if($Workspace){
    $page=Invoke-WebRequest -Uri $studioUrl -UseBasicParsing -TimeoutSec 3
    $tokenMatch=[regex]::Match($page.Content,'name="sakura-token" content="([^"]+)"')
    if(!$tokenMatch.Success){throw '无法读取本地会话验证信息。'}
    $headers=@{'X-Sakura-Token'=$tokenMatch.Groups[1].Value}
    $current=Invoke-RestMethod -Uri ($studioUrl+'api/workspace') -Headers $headers -TimeoutSec 4
    if(!$current.job -or $current.job.state -ne 'running'){$null=Invoke-RestMethod -Uri ($studioUrl+'api/workspace/start') -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 4}
    if(!$Theme){OpenControl}
    return
  }
  if($Theme){
    $page=Invoke-WebRequest -Uri $studioUrl -UseBasicParsing -TimeoutSec 3
    $tokenMatch=[regex]::Match($page.Content,'name="sakura-token" content="([^"]+)"')
    if(!$tokenMatch.Success){throw '无法读取本地会话验证信息。'}
    $headers=@{'X-Sakura-Token'=$tokenMatch.Groups[1].Value}
    $null=Invoke-RestMethod -Uri ($studioUrl+'api/launch') -Method Post -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 25
    $showDeadline=[DateTime]::UtcNow.AddSeconds(30)
    while([DateTime]::UtcNow -lt $showDeadline){
      Start-Sleep -Milliseconds 600
      try{
        $confirmed=Invoke-RestMethod -Uri ($studioUrl+'api/status') -Headers $headers -TimeoutSec 25
        if($confirmed.desktop.active -and $confirmed.connection.owned -and $confirmed.connection.window.visible -and !$confirmed.connection.window.minimized){return}
      }catch{}
    }
    throw '主界面显示未确认。请从任务栏选择专用窗口，或手动打开樱色工坊查看连接状态。'
  }
  OpenControl
}
$existing=$null
try {$existing=Invoke-RestMethod -Uri ($studioUrl+'health') -TimeoutSec 2}catch{}
if($existing){
  if($existing.service -ne 'sakura-studio'){throw '56895 端口已被其他服务占用。'}
  if($existing.version -ne $expectedVersion){throw '旧版控制中心仍在运行，请先在旧版中点击“关闭工具”，再启动本版。不要直接结束桌面应用。'}
  if($existing.installationId -ne $expectedInstallation){throw '另一目录的工具副本正在运行。请使用原目录入口，或先关闭旧副本；不会跨目录接管。'}
  OpenStudio
  exit
}
New-Item -ItemType Directory -Path (Join-Path $root 'state') -Force|Out-Null
$log=Join-Path $root 'state\server.log'
$errorLog=Join-Path $root 'state\server-error.log'
$serverPath=Join-Path $root 'server.mjs'
$serverProcess=Start-Process -FilePath $node -ArgumentList ('"'+$serverPath+'"') -WorkingDirectory $root -WindowStyle Hidden -RedirectStandardOutput $log -RedirectStandardError $errorLog -PassThru
for($attempt=0;$attempt -lt 40;$attempt++){
  Start-Sleep -Milliseconds 200
  if($serverProcess.HasExited){throw ('后台已退出，请查看 '+$errorLog)}
  $health=$null
  try{$health=Invoke-RestMethod -Uri ($studioUrl+'health') -TimeoutSec 1}catch{}
  if($health -and $health.service -eq 'sakura-studio' -and $health.version -eq $expectedVersion -and $health.pid -eq $serverProcess.Id){OpenStudio;exit}
}
throw ('控制中心未能启动，请查看 '+$errorLog)
} catch {
  $startupMessage=$_.Exception.Message
  try{$detail=$_.ErrorDetails.Message|ConvertFrom-Json;if($detail.error){$startupMessage=[string]$detail.error}}catch{}
  try {
    $startupRoot=Split-Path -Parent $MyInvocation.MyCommand.Path
    $startupState=Join-Path $startupRoot 'state'
    New-Item -ItemType Directory -Path $startupState -Force|Out-Null
    [IO.File]::WriteAllText((Join-Path $startupState 'startup-error.log'),([DateTime]::Now.ToString('s')+"`r`n"+$startupMessage),[Text.UTF8Encoding]::new($true))
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show(('启动未完成：'+$startupMessage+"`n`n请保留此提示，便于修复。"),'樱色工坊',[System.Windows.MessageBoxButton]::OK,[System.Windows.MessageBoxImage]::Error)|Out-Null
  } catch {}
  exit 1
}
