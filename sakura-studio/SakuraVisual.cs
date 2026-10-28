using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using System.Windows.Automation;

internal sealed class SakuraVisual : Window {
  private readonly string mode, readyFile;
  private readonly DispatcherTimer timer = new DispatcherTimer();
  private MenuItem follow;
  private int ticks;
  private bool shown, failed;
  private string failure;
  private static Brush Brush(string hex){return (Brush)new BrushConverter().ConvertFromString(hex);}
  [StructLayout(LayoutKind.Sequential)] private struct Rect {public int Left,Top,Right,Bottom;}
  [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr handle,out Rect rect);
  [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr handle);
  private void Record(string state,string error){
    if(String.IsNullOrEmpty(readyFile))return;
    try{File.WriteAllText(readyFile,"{\"mode\":\""+mode+"\",\"state\":\""+state+"\",\"shown\":"+(shown?"true":"false")+",\"pid\":"+Process.GetCurrentProcess().Id+",\"error\":\""+(error??"").Replace("\\","\\\\").Replace("\"","\\\"").Replace("\r"," ").Replace("\n"," ")+"\"}");}catch{}
  }
  private SakuraVisual(string mode,string image,string readyFile){
    this.mode=mode;this.readyFile=readyFile;
    Title=mode=="Boot"?"樱色工坊 · 启动开场":"樱色工坊 · 角色小窗";
    Width=mode=="Boot"?420:260;Height=mode=="Boot"?310:338;
    WindowStartupLocation=WindowStartupLocation.CenterScreen;WindowStyle=WindowStyle.None;
    AllowsTransparency=true;Background=Brushes.Transparent;ResizeMode=ResizeMode.NoResize;ShowInTaskbar=true;
    var border=new Border{Background=Brush("#F0251B2C"),CornerRadius=new CornerRadius(16),Padding=new Thickness(8)};
    var stack=new StackPanel();
    var header=new DockPanel{Margin=new Thickness(5,0,0,5)};
    var close=new Button{Content="×",Foreground=Brush("#ECDFEF"),Background=Brushes.Transparent,BorderThickness=new Thickness(0),Width=25,Height=22,Padding=new Thickness(0)};
    AutomationProperties.SetName(close,"关闭角色小窗");close.Click+=delegate{Close();};DockPanel.SetDock(close,Dock.Right);header.Children.Add(close);
    header.Children.Add(new TextBlock{Text="樱色工坊",Foreground=Brush("#CDB4D6"),FontSize=11,VerticalAlignment=VerticalAlignment.Center});
    stack.Children.Add(header);
    var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.UriSource=new Uri(image,UriKind.Absolute);bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.EndInit();bitmap.Freeze();
    BitmapSource source=bitmap;
    if(mode=="Companion"){source=new CroppedBitmap(bitmap,new Int32Rect(0,0,(int)(bitmap.PixelWidth*.55),bitmap.PixelHeight));source.Freeze();}
    var picture=new Image{Source=source,Width=mode=="Boot"?404:244,Height=mode=="Boot"?225:265,Stretch=Stretch.UniformToFill};
    picture.Clip=new RectangleGeometry(new System.Windows.Rect(0,0,picture.Width,picture.Height),8,8);
    stack.Children.Add(picture);
    stack.Children.Add(new TextBlock{Text=mode=="Boot"?"准备开始 · Esc 跳过":"陪你专注 · 拖动即可移动",Foreground=Brush("#F1E5F4"),FontSize=12,Margin=new Thickness(7,9,0,0)});
    border.Child=stack;Content=border;
    if(mode=="Companion"){
      var menu=new ContextMenu();follow=new MenuItem{Header="跟随桌面窗口",IsCheckable=true};
      var exit=new MenuItem{Header="关闭角色小窗"};exit.Click+=delegate{Close();};menu.Items.Add(follow);menu.Items.Add(exit);border.ContextMenu=menu;
      timer.Interval=TimeSpan.FromSeconds(1);timer.Tick+=delegate{if(File.Exists(readyFile+".stop")){Close();return;}Follow();};
    }else{
      Opacity=.05;timer.Interval=TimeSpan.FromMilliseconds(40);
      timer.Tick+=delegate{if(File.Exists(readyFile+".stop")){Close();return;}ticks++;Opacity=ticks<10?ticks/10.0:(ticks>40?Math.Max(0,(50-ticks)/10.0):1);if(ticks>=50)Close();};
    }
    MouseLeftButtonDown+=delegate(object sender,MouseButtonEventArgs e){if(e.OriginalSource is Button)return;if(follow!=null)follow.IsChecked=false;try{DragMove();}catch(InvalidOperationException){} };
    KeyDown+=delegate(object sender,KeyEventArgs e){if(e.Key==Key.Escape)Close();};
    ContentRendered+=delegate{
      shown=true;if(mode=="Boot")Opacity=.1;
      try{var snapshot=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);snapshot.Render(border);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(snapshot));using(var file=File.Create(readyFile+".png"))png.Save(file);}catch(IOException){}
      Record("ready",null);timer.Start();
    };
    Closed+=delegate{timer.Stop();Record(failed?"error":"closed",failure);try{File.Delete(readyFile+".stop");}catch(IOException){} };
    Record("starting",null);
  }
  private void Follow(){
    if(follow==null||!follow.IsChecked)return;
    foreach(var process in Process.GetProcessesByName("ChatGPT")){
      try{
        var handle=process.MainWindowHandle;if(handle==IntPtr.Zero||IsIconic(handle))continue;
        Rect rect;if(!GetWindowRect(handle,out rect))continue;
        var source=PresentationSource.FromVisual(this);if(source==null)continue;
        var point=source.CompositionTarget.TransformFromDevice.Transform(new Point(rect.Right,rect.Bottom));
        Left=point.X-Width-18;Top=point.Y-Height-18;break;
      }catch(InvalidOperationException){}finally{process.Dispose();}
    }
  }
  [STAThread] public static int Main(string[] args){
    string ready=null;
    try{
      if(args.Length!=3||!(args[0]=="Companion"||args[0]=="Boot"))return 2;
      ready=args[2];var application=new Application();var window=new SakuraVisual(args[0],args[1],ready);
      application.DispatcherUnhandledException+=delegate(object sender,DispatcherUnhandledExceptionEventArgs e){window.failed=true;window.failure=e.Exception.Message;window.Record("error",e.Exception.Message);e.Handled=true;window.Close();};
      application.Run(window);return 0;
    }catch(Exception){if(ready!=null)try{File.WriteAllText(ready,"{\"state\":\"error\",\"error\":\"Native visual startup failed\"}");}catch{}return 1;}
  }
}
