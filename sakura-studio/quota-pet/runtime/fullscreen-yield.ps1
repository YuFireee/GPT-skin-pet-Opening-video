Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using System.Diagnostics;
public static class SakuraFullscreen {
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; public Rect(int l,int t,int r,int b){Left=l;Top=t;Right=r;Bottom=b;} }
 [StructLayout(LayoutKind.Sequential)] struct Monitor {public int size;public Rect bounds,work;public uint flags;}
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out Rect rect);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsIconic(IntPtr h);
 [DllImport("user32.dll")] static extern bool IsZoomed(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr MonitorFromWindow(IntPtr h,uint flags);
 [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr h,ref Monitor monitor);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h,StringBuilder text,int size);
 public static bool Covers(bool visible,bool minimized,bool maximized,bool sameMonitor,bool own,Rect window,Rect monitor) {
  if(!visible||minimized||maximized||!sameMonitor||own)return false;
  return monitor.Right>monitor.Left&&monitor.Bottom>monitor.Top&&Math.Abs(window.Left-monitor.Left)<=2&&Math.Abs(window.Top-monitor.Top)<=2&&Math.Abs(window.Right-monitor.Right)<=2&&Math.Abs(window.Bottom-monitor.Bottom)<=2;
 }
 public static uint Owner(IntPtr h){uint pid;GetWindowThreadProcessId(h,out pid);return pid;}
 public static bool TransientName(string name) {
  switch((name??"").ToLowerInvariant()){
   case "screenclippinghost":case "snippingtool":case "snipaste":case "qqscreenshot":case "screencapture":case "sharex":case "lightshot":return true;default:return false;
  }
 }
 public static bool Transient(IntPtr h){
  try{using(var p=Process.GetProcessById((int)Owner(h))){return TransientName(p.ProcessName);}}catch{return false;}
 }
 public static bool Browser(IntPtr h){
  try{using(var p=Process.GetProcessById((int)Owner(h))){
   switch(p.ProcessName.ToLowerInvariant()){case "msedge":case "chrome":case "firefox":case "brave":case "vivaldi":case "opera":case "floorp":case "librewolf":case "thorium":case "chromium":return true;default:return false;}
  }}catch{return false;}
 }
 public static bool Detect(IntPtr widget,uint owner) {
  var h=GetForegroundWindow();if(h==IntPtr.Zero||h==widget)return false;
  uint pid;GetWindowThreadProcessId(h,out pid);if(pid==owner)return false;
  var name=new StringBuilder(128);GetClassName(h,name,128);var cls=name.ToString();
  if(cls=="Progman"||cls=="WorkerW"||cls.Contains("TrayWnd"))return false;
  var monitor=MonitorFromWindow(h,2);if(monitor==IntPtr.Zero||monitor!=MonitorFromWindow(widget,2))return false;
  var info=new Monitor();info.size=Marshal.SizeOf(typeof(Monitor));Rect rect;
  if(!GetMonitorInfo(monitor,ref info)||!GetWindowRect(h,out rect))return false;
  return Covers(IsWindowVisible(h),IsIconic(h),IsZoomed(h)&&!Browser(h),true,false,rect,info.bounds);
 }
}
'@
function Update-WidgetFullscreen([long]$Now,[scriptblock]$Probe=$null){
  if($Now-$script:fullscreenCheckedAt-lt 500){return}
  $script:fullscreenCheckedAt=$Now
  $candidate=$false
  if($script:fullscreenYieldOn){try{$candidate=if($Probe){[bool](&$Probe)}else{Get-VideoAwareFullscreen $Now}}catch{}}
  if(!$script:fullscreenYieldOn){Stop-VideoFullscreenProbe}
  if($candidate-ne $script:fullscreenCandidate){$script:fullscreenCandidate=$candidate;$script:fullscreenCandidateSince=$Now;return}
  if($candidate-eq $script:fullscreenYielded -or $Now-$script:fullscreenCandidateSince-lt 600){return}
  $script:fullscreenYielded=$candidate;$script:fullscreenLayerApplied=$false
  if($candidate){
    Close-QuotaCard -Immediate
    if($script:settingsPanel){$script:settingsPanel.Tag="immediate";$script:settingsPanel.Close()}
    if($script:activityPanel){$script:activityPanel.Tag='immediate';$script:activityPanel.Close()}
    if($script:context){$script:context.IsOpen=$false}
    if(!$script:collapsed){Hide-Quota}
  }else{
    [GptWidgetNative]::SetWindowPos($script:widgetHandle,[IntPtr]::Zero,0,0,0,0,0x13)|Out-Null
  }
}

# At most one bounded helper, only while a browser geometrically covers this screen.
function Stop-VideoFullscreenProbe {
  if($script:videoProbe){try{if(!$script:videoProbe.HasExited){$script:videoProbe.Kill()}}catch{};try{$script:videoProbe.Dispose()}catch{};$script:videoProbe=$null}
}
function Get-VideoAwareFullscreen([long]$Now) {
  $foreground=[SakuraFullscreen]::GetForegroundWindow()
  if([SakuraFullscreen]::Transient($foreground)){
    $script:fullscreenReason='截屏工具临时置前，保持原显隐状态'
    return [bool]$script:fullscreenYielded
  }
  if(![SakuraFullscreen]::Detect($script:widgetHandle,[uint32]$PID)){
    Stop-VideoFullscreenProbe;$script:videoProbeKey=$null;$script:videoConfirmed=$false
    $script:fullscreenReason='未检测到同屏前台全屏';return $false
  }
  $handle=[SakuraFullscreen]::GetForegroundWindow()
  if(![SakuraFullscreen]::Browser($handle)){
    Stop-VideoFullscreenProbe;$script:videoProbeKey=$null;$script:videoConfirmed=$false;$script:fullscreenReason='原生应用全屏';return $true
  }
  $owner=[SakuraFullscreen]::Owner($handle);$key=$handle.ToInt64().ToString()+':'+$owner
  if($script:videoProbeKey-ne $key){Stop-VideoFullscreenProbe;$script:videoProbeKey=$key;$script:videoConfirmed=$false;$script:videoProbeNext=0}
  # A confirmed DOM-fullscreen session stays yielded while this same browser
  # still covers the monitor; auto-hidden player controls do not undo confirmation.
  if($script:videoConfirmed){$script:fullscreenReason='网页视频全屏已确认，持续隐藏';return $true}
  if($script:videoProbe){
    $script:videoProbe.Refresh()
    if($script:videoProbe.HasExited){
      $result=$script:videoProbe.ExitCode;Stop-VideoFullscreenProbe
      $script:videoConfirmed=($result-eq 0);$script:videoProbeNext=$Now+$(if($result-eq 0){4000}elseif($result-eq 2){10000}else{60000})
      $script:fullscreenReason=if($result-eq 0){'网页视频全屏已确认'}elseif($result-eq 2){'浏览器全屏：无视频退出控件证据，保留桌宠'}else{'视频检测不可用，暂停60秒'}
    }elseif($Now-$script:videoProbeAt-ge 1800 -or $script:videoProbe.PrivateMemorySize64-gt 128MB){
      Stop-VideoFullscreenProbe;$script:videoConfirmed=$false;$script:videoProbeNext=$Now+60000;$script:fullscreenReason='视频检测超时或资源超限，暂停60秒'
    }
  }elseif($Now-ge $script:videoProbeNext){
    $file=Join-Path $script:appDir 'runtime/VideoFullscreenProbe.exe'
    if(!(Test-Path -LiteralPath $file)){
      $script:videoProbeNext=$Now+60000;$script:fullscreenReason='缺少视频检测组件，请重新构建'
    }else{
      try{
        $start=[Diagnostics.ProcessStartInfo]::new($file,($handle.ToInt64().ToString()+' '+$owner))
        $start.UseShellExecute=$false;$start.CreateNoWindow=$true
        $script:videoProbe=[Diagnostics.Process]::Start($start);$script:videoProbeAt=$Now
        $script:fullscreenReason='正在确认网页视频全屏'
      }catch{$script:videoProbeNext=$Now+60000;$script:fullscreenReason='无法启动视频检测，暂停60秒'}
    }
  }
  return [bool]$script:videoConfirmed
}
