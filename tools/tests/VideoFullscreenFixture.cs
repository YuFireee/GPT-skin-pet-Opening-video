using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation.Peers;
using System.Windows.Interop;
using System.Windows.Threading;
public sealed class WebDocument : StackPanel {
 protected override AutomationPeer OnCreateAutomationPeer(){return new WebDocumentPeer(this);}
}
public sealed class WebDocumentPeer : FrameworkElementAutomationPeer {
 public WebDocumentPeer(WebDocument owner):base(owner){}
 protected override AutomationControlType GetAutomationControlTypeCore(){return AutomationControlType.Document;}
 protected override string GetClassNameCore(){return "FixtureDocument";}
}
public static class VideoFullscreenFixture {
 [STAThread] public static int Main(string[] args){
  if(args.Length==2&&args[0]=="--inspect")return VideoFullscreenProbe.Inspect(new IntPtr(long.Parse(args[1])));
  if(!VideoFullscreenProbe.WebFullscreenNotice("bilibili.com 若要退出全屏，请按 Esc")||VideoFullscreenProbe.WebFullscreenNotice("按 F11 退出全屏"))return 13;
  if(!VideoFullscreenProbe.VideoControl("退出全屏",true,true)||VideoFullscreenProbe.VideoControl("退出全屏",false,true)||VideoFullscreenProbe.VideoControl("退出全屏",true,false)||VideoFullscreenProbe.VideoControl("全屏",true,true))return 10;
  var app=new Application();var window=new Window{Width=320,Height=150,Title="Isolated video detector fixture",Left=20,Top=20};
  var button=new Button{Content="退出全屏",Width=150,Height=50};var document=new WebDocument();document.Children.Add(button);window.Content=document;
  Process child=null;int stage=0,result=0;var started=Stopwatch.StartNew();var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(50)};
  window.Loaded+=(s,e)=>{window.Activate();timer.Start();};
  timer.Tick+=(s,e)=>{
   if(started.ElapsedMilliseconds>12000){result=11;window.Close();return;}
   if(child==null){
    if(started.ElapsedMilliseconds<400)return;
    var hwnd=new WindowInteropHelper(window).Handle;
    child=Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--inspect "+hwnd.ToInt64()){UseShellExecute=false,CreateNoWindow=true});return;
   }
   if(!child.HasExited)return;
   int expected=(stage==0||stage==3)?0:2;
   if(child.ExitCode!=expected){Console.WriteLine("stage "+stage+" expected "+expected+" got "+child.ExitCode);result=12;window.Close();return;}
   child.Dispose();child=null;stage++;
   if(stage==1){button.Content="全屏";}
   else if(stage==2){document.Children.Remove(button);var toolbar=new StackPanel();button.Content="退出全屏";toolbar.Children.Add(button);window.Content=toolbar;}
   else if(stage==3){var customDocument=new WebDocument();customDocument.Children.Add(new TextBlock{Text="退出全屏"});window.Content=customDocument;}
   else window.Close();
  };
  window.Closed+=(s,e)=>{timer.Stop();if(child!=null){if(!child.HasExited)child.Kill();child.Dispose();}};
  app.Run(window);if(result==0)Console.WriteLine("Video probe passed: accessible web-video exit, normal fullscreen action, F11 toolbar exclusion, non-button web controls and Esc notice");return result;
 }
}
