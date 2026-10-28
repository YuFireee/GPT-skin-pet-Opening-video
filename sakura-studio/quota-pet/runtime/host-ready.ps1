# Read only the accessibility tree; a visible Chromium HWND also exists while
# the app is still showing its loading screen. Do not interact with its controls.
# The integrated launcher already waits for its main UI. Avoid traversing the
# accessibility tree of a long conversation merely to place the pet window.
if($script:config.readinessMode -ne 'native-window'){
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,WindowsBase
if(!('GptWidgetHostReadiness' -as [type])){
Add-Type -TypeDefinition @'
using System;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
public static class GptWidgetHostReadiness {
 static readonly object Gate=new object();
 static IntPtr target;
 static Task<bool> pending;
 static Task<bool> StartProbe(IntPtr handle){
  return Task.Factory.StartNew(()=>HasInterface(handle),CancellationToken.None,TaskCreationOptions.LongRunning,TaskScheduler.Default);
 }
 // UI Automation can wait on an unresponsive app. Keep all provider calls off
 // the WPF Dispatcher, with at most one outstanding probe per active host.
 public static bool Poll(IntPtr handle){
  lock(Gate){
   if(target!=handle){if(pending!=null&&!pending.IsCompleted)return false;target=handle;pending=null;}
   if(handle==IntPtr.Zero)return false;
   if(pending==null){pending=StartProbe(handle);return false;}
   if(!pending.IsCompleted)return false;
   bool ready=pending.Status==TaskStatus.RanToCompletion&&pending.Result;
   pending=StartProbe(handle);
   return ready;
  }
 }
 public static bool HasInterface(IntPtr handle){
  if(handle==IntPtr.Zero)return false;
  try{
   var root=AutomationElement.FromHandle(handle);
   var usable=new AndCondition(new PropertyCondition(AutomationElement.IsEnabledProperty,true),new PropertyCondition(AutomationElement.IsOffscreenProperty,false));
   var input=root.FindFirst(TreeScope.Descendants,new AndCondition(usable,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit)));
   if(input!=null)return true;
   var buttons=root.FindAll(TreeScope.Descendants,new AndCondition(usable,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)));
   for(int i=0;i<buttons.Count;i++){
    string name=buttons[i].Current.Name??"";
    if(Regex.IsMatch(name,@"^(new (thread|chat|conversation)|settings|\u65b0\u7ebf\u7a0b|\u65b0\u5efa\u7ebf\u7a0b|\u65b0\u804a\u5929|\u65b0\u5bf9\u8bdd|\u65b0\u5efa\u5bf9\u8bdd|\u8bbe\u7f6e)(\s|$)",RegexOptions.IgnoreCase))return true;
   }
  }catch{}
  return false;
 }
}
'@ -ReferencedAssemblies ([Windows.Automation.AutomationElement].Assembly.Location),([Windows.Automation.ControlType].Assembly.Location),([Windows.Point].Assembly.Location)
}
}
function New-WidgetReadinessState {
  return [pscustomobject]@{host=[IntPtr]::Zero;ready=$false;candidate=$false;lastProbe=-1000L;desktopStarted=$false}
}
function Test-WidgetHostReady {
  param($State,[IntPtr]$HostHandle,[long]$Now,[scriptblock]$Probe={param($h)
    if($script:config.readinessMode -eq 'native-window'){
      if(![GptWidgetNative]::IsWindow($h) -or ![GptWidgetZOrderNative]::VisibleSurface($h) -or [GptWidgetNative]::IsIconic($h)){return $false}
      $frame=[GptWidgetNative]::Frame($h);return ($frame.Right-$frame.Left -ge 300 -and $frame.Bottom-$frame.Top -ge 200)
    }
    [GptWidgetHostReadiness]::Poll($h)
  })
  if($State.host-ne $HostHandle){$State.host=$HostHandle;$State.ready=$false;$State.candidate=$false;$State.lastProbe=$Now-1000}
  if($HostHandle-eq [IntPtr]::Zero){return $false}
  if($State.ready){return $true}
  if($Now-$State.lastProbe-lt 1000){return $false}
  $State.lastProbe=$Now
  $hasInterface=[bool](& $Probe $HostHandle)
  # Require two stable samples, rather than a fixed startup delay.
  if($hasInterface -and $State.candidate){$State.ready=$true}
  $State.candidate=$hasInterface
  return [bool]$State.ready
}

# A still-valid hidden host must not prevent discovery of another visible main window.
function Update-WidgetHostCandidate {
  param([bool]$CurrentVisible,[long]$Now,[scriptblock]$FindVisible={ [GptWidgetNative]::FindCodex() })
  if($CurrentVisible -or $Now-$script:lastHostProbe-lt 1000){return $false}
  $script:lastHostProbe=$Now
  $candidate=[IntPtr](& $FindVisible)
  if($candidate-ne [IntPtr]::Zero -and $candidate-ne $script:hostHandle){
    $script:hostHandle=$candidate;$script:lastPosition=$null;return $true
  }
  return $false
}
function Publish-WidgetVisibility {
  param([string]$Path,[bool]$Visible)
  if(!$Path){return}
  $state=if($Visible){'ready'}else{'waiting'}
  if($script:lastPublishedDisplayState-eq $state){return}
  Write-WidgetJson $Path @{state=$state;shown=$Visible;pid=$PID}
  $script:lastPublishedDisplayState=$state
}
