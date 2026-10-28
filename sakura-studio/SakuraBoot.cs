using System;
using System.IO;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using ShapePath=System.Windows.Shapes.Path;
using System.Windows.Threading;

internal sealed class SakuraBoot : Window {
  const double Duration=6.4;
  readonly BootHandoff handoff=new BootHandoff();
  BootEscape escape;
  readonly bool useHandoff;
  readonly Canvas stage=new Canvas();
  readonly Border screen=new Border{Background=Ink("#241B2B"),BorderBrush=Ink("#DDB8D6"),BorderThickness=new Thickness(5),CornerRadius=new CornerRadius(12)};
  readonly TextBlock hint=new TextBlock();
  double connectedAt=-1;
  bool completedLive;
  System.Windows.Rect initialBounds;
  readonly string receipt;
  readonly bool capture;
  readonly Stopwatch clock=new Stopwatch();
  readonly DispatcherTimer timer=new DispatcherTimer();
  readonly Grid scene=new Grid();
  readonly Canvas petals=new Canvas{IsHitTestVisible=false};
  readonly ScaleTransform camera=new ScaleTransform(1.02,1.02);
  readonly ShapePath[] flowers=new ShapePath[22];
  bool shown;
  int frame;
  string reason="completed";
  static Brush Ink(string value){return (Brush)new BrushConverter().ConvertFromString(value);}
  void Record(string state){
    var json="{\"state\":\""+state+"\",\"mode\":\"Boot\",\"shown\":"+(shown?"true":"false")+",\"pid\":"+Process.GetCurrentProcess().Id+",\"reason\":\""+reason+"\",\"handoff\":\""+(completedLive?"live-window":useHandoff?"fade-fallback":"preview")+"\",\"elapsed\":"+clock.Elapsed.TotalSeconds.ToString("0.000",CultureInfo.InvariantCulture)+"}";
    string temp=receipt+".tmp";File.WriteAllText(temp,json);
    if(File.Exists(receipt))File.Replace(temp,receipt,null);else File.Move(temp,receipt);
  }
  void Finish(string value){reason=value;Close();}
  SakuraBoot(string image,string ready,bool frames,bool liveEnabled){
    receipt=ready;capture=frames;useHandoff=liveEnabled;Title="樱色工坊 · 花影开场";
    Width=Math.Min(960,SystemParameters.WorkArea.Width*.84);Height=Width*9/16;
    WindowStartupLocation=WindowStartupLocation.CenterScreen;WindowStyle=WindowStyle.None;
    ResizeMode=ResizeMode.NoResize;Background=Brushes.Black;ShowInTaskbar=false;Topmost=true;
    var bitmap=new BitmapImage();bitmap.BeginInit();bitmap.UriSource=new Uri(image,UriKind.Absolute);bitmap.CacheOption=BitmapCacheOption.OnLoad;bitmap.EndInit();bitmap.Freeze();
    scene.ClipToBounds=true;scene.Background=new LinearGradientBrush(Color.FromRgb(71,38,71),Color.FromRgb(27,20,40),35);
    var picture=new Image{Source=bitmap,Stretch=Stretch.UniformToFill,RenderTransformOrigin=new Point(.3,.5),RenderTransform=camera};scene.Children.Add(picture);
    var veil=new Rectangle{Fill=new LinearGradientBrush(new GradientStopCollection{new GradientStop(Color.FromArgb(0,25,13,30),0),new GradientStop(Color.FromArgb(90,25,13,30),1)},90),IsHitTestVisible=false};scene.Children.Add(veil);
    scene.Children.Add(petals);
    scene.Children.Add(stage);stage.Children.Add(screen);
    screen.Child=new TextBlock{Text="等待工作空间",Foreground=Ink("#CAB7CF"),FontSize=20,HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center};
    for(int i=0;i<flowers.Length;i++){
      var p=new ShapePath{Data=Geometry.Parse("M0,0 C-8,-9 -10,-1 -5,5 C0,10 8,5 7,0 C5,-4 2,-3 0,0 Z"),Fill=Ink(i%3==0?"#FFF1F6":"#EDB6D0"),Opacity=.5};
      p.RenderTransformOrigin=new Point(.5,.5);flowers[i]=p;petals.Children.Add(p);
    }
    var title=new TextBlock{Text="樱色工坊 · 即将进入工作空间",FontFamily=new FontFamily("Microsoft YaHei UI"),FontSize=18,Foreground=Ink("#FFF2FA"),Margin=new Thickness(30),HorizontalAlignment=HorizontalAlignment.Left,VerticalAlignment=VerticalAlignment.Bottom};scene.Children.Add(title);
    hint.Text=useHandoff?"正在准备实时窗口…":"演示模式 · 屏幕展开预览";hint.Foreground=Ink("#EAD8E9");hint.FontSize=12;hint.HorizontalAlignment=HorizontalAlignment.Center;hint.VerticalAlignment=VerticalAlignment.Top;hint.Margin=new Thickness(0,20,0,0);scene.Children.Add(hint);

    bool canSkip=false;Action trySkip=()=>{if(File.Exists(receipt+".desktop-ready")&&handoff.SourceAvailable(receipt+".target"))Finish("skipped");};
    var skip=new Button{Visibility=Visibility.Collapsed,Content="Esc 跳过",FontSize=11,Foreground=Ink("#F3DAEA"),Background=Ink("#48271A32"),BorderThickness=new Thickness(0),Padding=new Thickness(10,5,10,5),Margin=new Thickness(20),HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Top};skip.Click+=delegate{trySkip();};scene.Children.Add(skip);Content=scene;
    Opacity=0;
    PreviewKeyDown+=delegate(object sender,KeyEventArgs e){if(e.Key==Key.Escape){e.Handled=true;}};
    timer.Interval=TimeSpan.FromMilliseconds(1000.0/30);
    timer.Tick+=delegate{
      if(File.Exists(receipt+".stop")){Finish("stopped");return;}
      canSkip=File.Exists(receipt+".desktop-ready")&&handoff.SourceAvailable(receipt+".target");skip.Visibility=canSkip?Visibility.Visible:Visibility.Collapsed;
      double wall=clock.Elapsed.TotalSeconds;
      bool live=useHandoff&&handoff.Connect(this,receipt+".target");
      if(useHandoff&&connectedAt<0&&(live||handoff.Failed||wall>23))connectedAt=wall;
      double t=useHandoff?(wall<3?wall:connectedAt<0?3:3+Math.Max(0,wall-Math.Max(3,connectedAt))):wall;
      if(useHandoff&&connectedAt<0&&wall>=3)hint.Text="等待客户端主界面";
      else if(live)hint.Text="实时窗口已接入";
      else if(useHandoff&&connectedAt>=0)hint.Text="实时连接不可用 · 淡出进入";
      double unfold=Smooth(Math.Min(1,t/1.6));
      double transition=Smooth(Math.Max(0,Math.Min(1,(t-4.1)/2.3)));
      if(transition>0&&live){var bounds=handoff.Bounds(this);if(!bounds.IsEmpty){Left=initialBounds.Left+(bounds.Left-initialBounds.Left)*transition;Top=initialBounds.Top+(bounds.Top-initialBounds.Top)*transition;Width=initialBounds.Width+(bounds.Width-initialBounds.Width)*transition;Height=initialBounds.Height+(bounds.Height-initialBounds.Height)*transition;}}
      double w=ActualWidth,h=ActualHeight;
      double sx=w*.48*(1-transition),sy=h*.16*(1-transition),sw=w*(.49+.51*transition),sh=h*(.66+.34*transition);
      screen.Width=sw;screen.Height=Math.Max(1,sh*unfold);Canvas.SetLeft(screen,sx);Canvas.SetTop(screen,sy+(sh-screen.Height)/2);
      screen.Opacity=unfold;
      title.Opacity=hint.Opacity=1-transition;
      if(live&&unfold>.99){handoff.Draw(this,sx+5*(1-transition),sy+5*(1-transition),sw-10*(1-transition),sh-10*(1-transition),Math.Min(1,(t-1.6)/.7));}

      Opacity=Math.Max(0,Math.Min(1,t/.48));if(!live&&t>Duration-.55)Opacity=Math.Max(0,(Duration-t)/.55);
      camera.ScaleX=camera.ScaleY=1.02+.045*Math.Min(1,t/Duration);
      for(int i=0;i<flowers.Length;i++){
        double x=((i*167.0+t*(32+i%5*7))%(Width+140))-70;
        double y=((i*97.0+t*(20+i%4*8))%(Height+90))-45+Math.Sin(t*1.6+i)*12;
        Canvas.SetLeft(flowers[i],x);Canvas.SetTop(flowers[i],y);
        var transform=new TransformGroup();transform.Children.Add(new ScaleTransform(.55+i%4*.16,.55+i%4*.16));transform.Children.Add(new RotateTransform(i*23+t*(22+i%3*18)));flowers[i].RenderTransform=transform;
      }
      if(capture&&frame<3&&t>=new double[]{.9,2.2,3.6}[frame]){SaveFrame(frame++);}
      if(t>=Duration){completedLive=live;Finish("completed");}
    };
    ContentRendered+=delegate{escape=new BootEscape(this,trySkip,()=>canSkip);shown=true;initialBounds=new System.Windows.Rect(Left,Top,Width,Height);clock.Start();Record("ready");timer.Start();};
    Closed+=delegate{if(escape!=null)escape.Dispose();timer.Stop();handoff.Dispose();Record("closed");try{File.Delete(receipt+".stop");}catch(IOException){}};
  }
  static double Smooth(double t){return t*t*(3-2*t);}
  void SaveFrame(int index){var bitmap=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(scene);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(bitmap));using(var f=File.Create(receipt+".frame-"+index+".png"))png.Save(f);}
  [STAThread] public static int Main(string[] args){
    if(args.Length<3||args[0]!="Boot")return 2;
    try{int video=Array.IndexOf(args,"--video");if(video>=0&&video+1<args.Length){MovieBoot.Run(args[1],args[video+1],args[2],Array.IndexOf(args,"--frames")>=0,Array.IndexOf(args,"--handoff")>=0,Array.IndexOf(args,"--sound")>=0,Array.IndexOf(args,"--wait-ready")>=0,Array.IndexOf(args,"--background-main")>=0);return 0;}var app=new Application();app.Run(new SakuraBoot(args[1],args[2],Array.IndexOf(args,"--frames")>=0,Array.IndexOf(args,"--handoff")>=0));return 0;}
    catch{return 1;}
  }
}

