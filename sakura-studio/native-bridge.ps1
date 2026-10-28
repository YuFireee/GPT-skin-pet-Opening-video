param([ValidateSet('Inspect','Launch','Show','StopManaged','Reveal','LaunchBackground')][string]$Action='Inspect',[Parameter(Mandatory=$true)][string]$Profile,[double]$AspectRatio=1.777777778,[long]$WindowHandle=0,[uint32]$ExpectedPid=0,[string]$ExpectedCreated='',[ValidateRange(1024,65535)][int]$DebugPort=9335)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=New-Object System.Text.UTF8Encoding($false)
if(!('SakuraTcp' -as [type])){
  $tcpLibrary=Join-Path $PSScriptRoot 'NativeTcp.dll'
  if(Test-Path -LiteralPath $tcpLibrary){Add-Type -Path $tcpLibrary}else{Add-Type -Path (Join-Path $PSScriptRoot 'NativeTcp.cs')}
}
$runningApps=@(Get-Process ChatGPT -ErrorAction SilentlyContinue)
$apps=@()
$identityReadable=$true
try {$apps=@(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction Stop)}catch{$identityReadable=$false}
$managedRoots=@($apps | Where-Object {$_.CommandLine -and $_.CommandLine.Contains($Profile) -and $_.CommandLine -notmatch '--type='})
$listeners=@([SakuraTcp]::Listeners($DebugPort))
$registeredPackage=Get-AppxPackage -Name 'OpenAI.Codex' | Select-Object -First 1
$trustedExecutable=if($registeredPackage){Join-Path $registeredPackage.InstallLocation 'app\ChatGPT.exe'}else{''}
function Test-TrustedExecutable([string]$Candidate){
  if(!$Candidate -or !$trustedExecutable){return $false}
  if($Candidate -eq $trustedExecutable){return $true}
  $base=[regex]::Escape((Split-Path -Parent $registeredPackage.InstallLocation))
  $publisher=[regex]::Escape($registeredPackage.PublisherId)
  if($Candidate -notmatch ('(?i)^'+$base+'\\OpenAI\.Codex_[0-9.]+_x64__'+$publisher+'\\app\\ChatGPT\.exe$')){return $false}
  Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
  $currentSignature=Get-AuthenticodeSignature -LiteralPath $trustedExecutable
  $candidateSignature=Get-AuthenticodeSignature -LiteralPath $Candidate
  return ($currentSignature.Status -eq 'Valid' -and $candidateSignature.Status -eq 'Valid' -and $currentSignature.SignerCertificate -and $candidateSignature.SignerCertificate -and $currentSignature.SignerCertificate.Subject -ceq $candidateSignature.SignerCertificate.Subject)
}
$owned=$false
if($listeners.Count -gt 0){
  $allValid=$true
  foreach($listener in $listeners){
    $owner=$apps | Where-Object { $_.ProcessId -eq $listener.OwningProcess }
    if($listener.LocalAddress -notin @('127.0.0.1','::1') -or !$owner -or !$trustedExecutable -or !(Test-TrustedExecutable $owner.ExecutablePath) -or $owner.CommandLine -notmatch ('--remote-debugging-port[= ]'+$DebugPort+'(?:\s|$)') -or !$owner.CommandLine.Contains($Profile)){$allValid=$false}
  }
  $owned=$allValid
}
if($Action -eq 'StopManaged'){
  $exact=@($managedRoots | Where-Object {$_.ProcessId -eq $ExpectedPid -and (Test-TrustedExecutable $_.ExecutablePath) -and $_.CreationDate.ToUniversalTime().ToString('o') -eq $ExpectedCreated})
  if(!$ExpectedPid -or !$ExpectedCreated -or $exact.Count -ne 1){throw '专用实例身份或创建时间已变化，未结束任何进程。'}
  $process=Get-Process -Id $ExpectedPid -ErrorAction Stop
  Stop-Process -InputObject $process -ErrorAction Stop
  $null=$process.WaitForExit(5000)
  @{stopped=$process.HasExited}|ConvertTo-Json -Compress
  exit
}
Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class SakuraManagedWindow {
  public delegate bool Callback(IntPtr hwnd, IntPtr state);
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback cb, IntPtr state);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool ShowWindowAsync(IntPtr hwnd,int command);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr hwnd,uint flags);
  public static bool IsForeground(IntPtr window) {
    var foreground=GetForegroundWindow();
    return foreground!=IntPtr.Zero && (foreground==window || GetAncestor(foreground,3)==window);
  }
  [StructLayout(LayoutKind.Sequential)] public struct RECT {public int l,t,r,b;}
  [StructLayout(LayoutKind.Sequential)] public struct POINT {public int x,y;}
  [StructLayout(LayoutKind.Sequential)] public struct PLACEMENT {public int length,flags,showCmd;public POINT min,max;public RECT normal;}
  [DllImport("user32.dll")] static extern bool GetWindowPlacement(IntPtr hwnd,ref PLACEMENT placement);
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hwnd,out RECT rect);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd,StringBuilder name,int length);
  public static IntPtr Find(uint owner,double aspect,long hint) {
    IntPtr found=IntPtr.Zero;double best=double.MaxValue;long largest=0;if(hint!=0){uint pid;var h=new IntPtr(hint);GetWindowThreadProcessId(h,out pid);var n=new StringBuilder(256);GetClassName(h,n,256);if(pid==owner&&n.ToString()=="Chrome_WidgetWin_1")return h;}
    EnumWindows((hwnd,state)=>{uint pid;GetWindowThreadProcessId(hwnd,out pid);if(pid==owner){var name=new StringBuilder(256);GetClassName(hwnd,name,256);RECT rect;GetWindowRect(hwnd,out rect);if(IsIconic(hwnd)){var placement=new PLACEMENT();placement.length=Marshal.SizeOf(typeof(PLACEMENT));if(GetWindowPlacement(hwnd,ref placement))rect=placement.normal;}long area=(long)(rect.r-rect.l)*(rect.b-rect.t);double difference=rect.b>rect.t?Math.Abs((double)(rect.r-rect.l)/(rect.b-rect.t)-aspect):double.MaxValue;if(name.ToString()=="Chrome_WidgetWin_1"&&area>10000&&(difference<best||(difference==best&&area>largest))){best=difference;largest=area;found=hwnd;}}return true;},IntPtr.Zero);
    return found;
  }
}
'@
$windowInfo=$null
if($owned){
  $managedPid=[uint32]$listeners[0].OwningProcess
  $managedWindow=[SakuraManagedWindow]::Find($managedPid,$AspectRatio,$WindowHandle)
  if($managedWindow -ne [IntPtr]::Zero){
    $windowInfo=@{pid=$managedPid;handle=$managedWindow.ToInt64();visible=[SakuraManagedWindow]::IsWindowVisible($managedWindow);minimized=[SakuraManagedWindow]::IsIconic($managedWindow);foreground=[SakuraManagedWindow]::IsForeground($managedWindow)}
  }
}
if($Action -eq 'Reveal'){
  if(!$owned -or !$windowInfo -or !$windowInfo.visible){throw 'Cannot restore an unverified or hidden window'}
  if($windowInfo.minimized){$null=[SakuraManagedWindow]::ShowWindowAsync($managedWindow,9)}
  @{restored=$true}|ConvertTo-Json -Compress
  exit
}
if($Action -eq 'Show'){throw '已停用强制显露隐藏窗口；请从控制中心按应用启动流程恢复。'}
if($Action -eq 'Inspect'){
  @{managedRootPid=$(if($owned){[int]$listeners[0].OwningProcess}else{0});managedRootCreated=$(if($owned){($apps|Where-Object ProcessId -eq $listeners[0].OwningProcess|Select-Object -First 1).CreationDate.ToUniversalTime().ToString('o')}else{''});managedProcessCount=$managedRoots.Count;listenerCount=$listeners.Count;running=($runningApps.Count -gt 0);owned=$owned;window=$windowInfo;reason=$(if($owned){''}elseif($listeners.Count){("无法确认本地端口 "+$DebugPort+" 属于本工具管理的桌面窗口，不会连接。")}else{'尚未开启本工具专用的换肤连接。'})} | ConvertTo-Json -Compress
  exit
}
if($owned -and $windowInfo){
  if($Action -eq 'Launch' -and $windowInfo.minimized){$null=[SakuraManagedWindow]::ShowWindowAsync($managedWindow,9)}
  @{started=$true;reused=$true;reason=''}|ConvertTo-Json -Compress
  exit
}
# A tray exit can leave a listener visible after its owning process has exited.
# Only an explicit launch gets a bounded grace period; Inspect never waits/retries.
if(!$owned -and $listeners.Count -gt 0 -and $Action -in @('Launch','LaunchBackground')){
  $exitDeadline=[DateTime]::UtcNow.AddSeconds(3)
  do{
    Start-Sleep -Milliseconds 500
    $listeners=@([SakuraTcp]::Listeners($DebugPort))
  }while($listeners.Count -gt 0 -and [DateTime]::UtcNow -lt $exitDeadline)
  if($listeners.Count -eq 0){
    try{
      $apps=@(Get-CimInstance Win32_Process -Filter "Name = 'ChatGPT.exe'" -ErrorAction Stop)
      $managedRoots=@($apps | Where-Object {$_.CommandLine -and $_.CommandLine.Contains($Profile) -and $_.CommandLine -notmatch '--type='})
    }catch{$identityReadable=$false}
  }
}
if(!$owned -and $managedRoots.Count -gt 0){@{started=$false;reason='专用窗口已在运行，但调试连接不可用。请仅关闭专用窗口后重新打开；当前普通会话无需退出。'}|ConvertTo-Json -Compress;exit}
if(!$identityReadable){throw '当前权限无法验证桌面进程身份，未启动换肤模式。'}
if(!$owned -and $listeners.Count -gt 0){
  $orphaned=$true
  foreach($listener in $listeners){
    try{$null=Get-Process -Id $listener.OwningProcess -ErrorAction Stop;$orphaned=$false}
    catch{if($_.FullyQualifiedErrorId -notlike 'NoProcessFoundForGivenId*'){$orphaned=$false}}
  }
  @{started=$false;portOrphaned=$orphaned;reason=$(if($orphaned){'上次退出后本地连接端口尚未释放。'}else{'换肤端口已被其他程序占用，未接管。'})}|ConvertTo-Json -Compress;exit
}
$package=Get-AppxPackage -Name 'OpenAI.Codex' | Select-Object -First 1
if(!$package){throw '未找到受支持的 OpenAI.Codex 桌面安装。'}
$exe=Join-Path $package.InstallLocation 'app\ChatGPT.exe'
if(!(Test-Path -LiteralPath $exe -PathType Leaf)){throw '未找到桌面应用启动文件。'}
New-Item -ItemType Directory -Path $Profile -Force | Out-Null
$arguments=@(('--remote-debugging-port='+$DebugPort),'--remote-debugging-address=127.0.0.1',('--user-data-dir="'+$Profile+'"'))
$launchStyle=if($Action -eq 'LaunchBackground'){'Minimized'}else{'Normal'}
Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle $launchStyle
@{started=$true;reused=$owned;reason=''}|ConvertTo-Json -Compress
