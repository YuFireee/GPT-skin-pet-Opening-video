using System;
using System.IO;
using System.Diagnostics;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

internal sealed class MovieBoot : Window {
  readonly Grid scene=new Grid();
  readonly MediaElement movie=new MediaElement {LoadedBehavior=MediaState.Manual,UnloadedBehavior=MediaState.Manual,Stretch=Stretch.Uniform};
  readonly Canvas stage=new Canvas {Visibility=Visibility.Collapsed};
  readonly BootHandoff handoff=new BootHandoff();
  BootEscape escape;
  Button skip;
  bool canSkip,sourceReleased;
  string sourceIdentity="";
  int sourceGeneration;
  readonly Stopwatch clock=new Stopwatch();
  readonly int processId=Process.GetCurrentProcess().Id;
  readonly DispatcherTimer timer=new DispatcherTimer();
  readonly string receipt,videoPath;
  readonly bool liveEnabled,capture,sound,backgroundMain;
  readonly LoadingLoop waitingLoop;
  int loopCaptured;
  readonly TextBlock preparing=new TextBlock {Text="正在准备工作空间…",Foreground=Brushes.White,Background=new SolidColorBrush(Color.FromArgb(180,35,23,43)),FontSize=14,Padding=new Thickness(14,8,14,8),Margin=new Thickness(24),VerticalAlignment=VerticalAlignment.Bottom,HorizontalAlignment=HorizontalAlignment.Center};
  readonly Image poster;
  readonly BitmapImage finalImage,tailImage;
  bool shown,liveCompleted,visibleFallback,opened,fitted,playStarted;
  string reason="completed",mediaState="loading";
  double endedAt=-1,transitionAt=-1,lastPosition,lastRecord,playbackStartedAt;
  double nativeWidth=1344,nativeHeight=768,pixelWidth,pixelHeight;
  Rect transitionFrame;
  int captured;
  static BitmapImage LoadImage(string file){var b=new BitmapImage();b.BeginInit();b.UriSource=new Uri(file,UriKind.Absolute);b.CacheOption=BitmapCacheOption.OnLoad;b.EndInit();b.Freeze();return b;}
  static string N(double n){return n.ToString("0.000",CultureInfo.InvariantCulture);}
  void Record(string state){
    string json="{\"state\":\""+state+"\",\"mode\":\"Boot\",\"shown\":"+(shown?"true":"false")+",\"pid\":"+processId+",\"reason\":\""+reason+"\",\"mediaState\":\""+mediaState+"\",\"mediaPosition\":"+N(lastPosition)+",\"handoff\":\""+(liveCompleted?"live-window":visibleFallback?"visible-window-fade":liveEnabled?"fade-fallback":"preview")+"\",\"elapsed\":"+N(clock.Elapsed.TotalSeconds)+",\"fit\":\"native-pixels-then-client\",\"sourceLocated\":"+(fitted?"true":"false")+",\"left\":"+N(Left)+",\"top\":"+N(Top)+",\"width\":"+N(Width)+",\"height\":"+N(Height)+",\"playbackPixelWidth\":"+N(pixelWidth)+",\"playbackPixelHeight\":"+N(pixelHeight)+",\"nativeVideoWidth\":"+N(nativeWidth)+",\"nativeVideoHeight\":"+N(nativeHeight)+",\"transition\":"+(transitionAt>=0?"true":"false")+",\"sound\":"+(sound?"true":"false")+"}";
    json=json.Substring(0,json.Length-1)+",\"waitingLoop\":"+(endedAt>=0&&transitionAt<0?"true":"false")+",\"loopTime\":"+N(waitingLoop==null?0:waitingLoop.Time)+",\"loopEntryOpacity\":"+N(waitingLoop==null?0:waitingLoop.EntryOpacity)+",\"backgroundHeld\":"+(handoff.BackgroundHeld?"true":"false")+",\"skipEnabled\":"+(canSkip?"true":"false")+",\"skipHintVisible\":"+(skip!=null&&skip.Visibility==Visibility.Visible?"true":"false")+",\"skipHintPosition\":\"top-right\",\"sourceGeneration\":"+sourceGeneration+"}";
    string temp=receipt+".tmp";File.WriteAllText(temp,json);if(File.Exists(receipt))File.Replace(temp,receipt,null);else File.Move(temp,receipt);
  }
  void EndMovie(bool failed){
    if(endedAt>=0)return;lastPosition=Math.Max(lastPosition,movie.Position.TotalSeconds);mediaState=failed?"failed":"ended";
    endedAt=clock.Elapsed.TotalSeconds;movie.Close();movie.Source=null;movie.Visibility=Visibility.Collapsed;poster.Source=failed?finalImage:tailImage;
    transitionFrame=new Rect(Left,Top,Width,Height);waitingLoop.Visibility=Visibility.Visible;Record("ready");
  }
  void Finish(string value){reason=value;Close();}
  void UpdateSkipState(){
    string identity="";try{identity=File.ReadAllText(receipt+".target").Trim();}catch(IOException){}
    if(identity!=sourceIdentity){sourceIdentity=identity;sourceReleased=false;sourceGeneration++;}
    bool ready=File.Exists(receipt+".desktop-ready")&&handoff.SourceAvailable(receipt+".target");
    canSkip=ready;skip.Visibility=ready?Visibility.Visible:Visibility.Collapsed;skip.IsEnabled=ready;
    if(escape==null)escape=new BootEscape(this,TrySkip,()=>canSkip);

  }
  void TrySkip(){UpdateSkipState();if(canSkip)Finish("skipped");}
  static double Smooth(double p){p=Math.Max(0,Math.Min(1,p));return p*p*(3-2*p);}
  void SetFrame(Rect r){if(Math.Abs(Left-r.Left)>.1)Left=r.Left;if(Math.Abs(Top-r.Top)>.1)Top=r.Top;if(Math.Abs(Width-r.Width)>.1)Width=r.Width;if(Math.Abs(Height-r.Height)>.1)Height=r.Height;}
  Rect Target(){var r=liveEnabled?handoff.TargetBounds(this,receipt+".target"):Rect.Empty;if(!r.IsEmpty)fitted=true;return r.IsEmpty?SystemParameters.WorkArea:r;}
  void FitPlayback(){
    Rect target=Target(),work=SystemParameters.WorkArea;
    var visual=PresentationSource.FromVisual(this);var from=visual==null?Matrix.Identity:visual.CompositionTarget.TransformFromDevice;
    var to=visual==null?Matrix.Identity:visual.CompositionTarget.TransformToDevice;
    var natural=from.Transform(new Point(nativeWidth,nativeHeight));
    double scale=Math.Min(1,Math.Min(Math.Min(target.Width,work.Width*.94)/natural.X,Math.Min(target.Height,work.Height*.94)/natural.Y));
    double w=natural.X*scale,h=natural.Y*scale;
    var frame=new Rect(target.Left+(target.Width-w)/2,target.Top+(target.Height-h)/2,w,h);
    var pixels=to.Transform(new Point(w,h));pixelWidth=pixels.X;pixelHeight=pixels.Y;SetFrame(frame);
  }
  MovieBoot(string image,string video,string ready,bool frames,bool live,bool audio,bool wait,bool background){
    receipt=ready;videoPath=video;capture=frames;liveEnabled=live;sound=audio;backgroundMain=background;Title="樱色工坊 · 柔光角色开场";
    WindowStartupLocation=WindowStartupLocation.Manual;WindowStyle=WindowStyle.None;ResizeMode=ResizeMode.NoResize;
    Background=new SolidColorBrush(Color.FromRgb(25,21,35));ShowInTaskbar=false;Topmost=true;
    finalImage=LoadImage(image);
    string first=Path.ChangeExtension(video,".poster.png"),last=Path.ChangeExtension(video,".end.png");
    var firstImage=File.Exists(first)?LoadImage(first):finalImage;
    tailImage=File.Exists(last)?LoadImage(last):finalImage;
    if(File.Exists(first)){nativeWidth=firstImage.PixelWidth;nativeHeight=firstImage.PixelHeight;}
    poster=new Image {Source=firstImage,Stretch=Stretch.Uniform};
    waitingLoop=new LoadingLoop(tailImage){Visibility=Visibility.Collapsed};
    movie.IsMuted=!audio;movie.Volume=audio ? 0.65 : 0;
    scene.ClipToBounds=true;scene.Children.Add(poster);scene.Children.Add(movie);scene.Children.Add(waitingLoop);scene.Children.Add(stage);scene.Children.Add(preparing);preparing.Visibility=Visibility.Collapsed;
    skip=new Button {Content="Esc 跳过",Visibility=Visibility.Collapsed,IsEnabled=false,FontSize=11,Foreground=Brushes.White,Background=new SolidColorBrush(Color.FromArgb(65,35,18,40)),BorderThickness=new Thickness(0),Padding=new Thickness(10,5,10,5),Margin=new Thickness(18),HorizontalAlignment=HorizontalAlignment.Right,VerticalAlignment=VerticalAlignment.Top};
    skip.Click+=delegate{TrySkip();};scene.Children.Add(skip);Content=scene;
    PreviewKeyDown+=delegate(object s,KeyEventArgs e){if(e.Key==Key.Escape){e.Handled=true;}};
    movie.MediaOpened+=delegate{opened=true;mediaState="playing";if(movie.NaturalVideoWidth>0){nativeWidth=movie.NaturalVideoWidth;nativeHeight=movie.NaturalVideoHeight;}FitPlayback();Record("ready");};
    movie.MediaEnded+=delegate{EndMovie(false);};movie.MediaFailed+=delegate{EndMovie(true);};
    SourceInitialized+=delegate{escape=new BootEscape(this,TrySkip,()=>canSkip);if(liveEnabled)handoff.Connect(this,receipt+".target");FitPlayback();};
    Loaded+=delegate{FitPlayback();};
    timer.Interval=TimeSpan.FromMilliseconds(1000.0/30);
    timer.Tick+=delegate{
      if(File.Exists(receipt+".stop")){Finish("stopped");return;}
      UpdateSkipState();
      if(backgroundMain&&!sourceReleased){handoff.HoldSource(receipt+".target");if(endedAt>=0&&canSkip){sourceReleased=true;handoff.ReleaseSource();}}
      double wall=clock.Elapsed.TotalSeconds;bool connected=liveEnabled&&handoff.Connect(this,receipt+".target");
      if(!playStarted){FitPlayback();playStarted=true;playbackStartedAt=wall;preparing.Visibility=Visibility.Collapsed;movie.Source=new Uri(videoPath,UriKind.Absolute);movie.Play();}
      if(endedAt<0){
        if(wall-lastRecord>.2){lastRecord=wall;Record("ready");}
        FitPlayback();if(opened)lastPosition=movie.Position.TotalSeconds;
        if((!opened&&wall-playbackStartedAt>12)||wall-playbackStartedAt>32)EndMovie(true);
        if(capture&&captured<3&&wall-playbackStartedAt>=new double[]{1.5,4.5,8.5}[captured])SaveFrame(captured++);
        return;
      }
      if(transitionAt<0){
        waitingLoop.Time=wall-endedAt;waitingLoop.InvalidateVisual();
        if(capture&&loopCaptured<4&&wall-endedAt>=new double[]{.12,.36,.8,2.1}[loopCaptured])SaveFrame(3+loopCaptured++);
        if(!liveEnabled||(handoff.Valid()&&File.Exists(receipt+".desktop-ready")))transitionAt=wall;
        if(wall-lastRecord>.2){lastRecord=wall;Record("ready");}
      }
      if(transitionAt<0)return;
      double p=Smooth((wall-transitionAt)/1.6);waitingLoop.Time=wall-endedAt;waitingLoop.Opacity=1-p;waitingLoop.InvalidateVisual();
      if(connected){
        Rect target=Target();SetFrame(new Rect(transitionFrame.Left+(target.Left-transitionFrame.Left)*p,transitionFrame.Top+(target.Top-transitionFrame.Top)*p,transitionFrame.Width+(target.Width-transitionFrame.Width)*p,transitionFrame.Height+(target.Height-transitionFrame.Height)*p));
        stage.Visibility=Visibility.Visible;connected=handoff.Draw(this,0,0,ActualWidth,ActualHeight,p);poster.Opacity=1-p;
      }
      if(!connected)Opacity=1-p;
      if(wall-lastRecord>.2){lastRecord=wall;Record("ready");}
      if(wall-transitionAt>=1.6){liveCompleted=connected;visibleFallback=!connected&&handoff.Valid();Finish("completed");}
    };
    ContentRendered+=delegate{shown=true;FitPlayback();clock.Start();Record("ready");timer.Start();};
    Closed+=delegate{if(escape!=null)escape.Dispose();timer.Stop();movie.Close();handoff.ReleaseSource();handoff.Dispose();canSkip=false;skip.Visibility=Visibility.Collapsed;Record("closed");try{File.Delete(receipt+".stop");File.Delete(receipt+".desktop-ready");}catch(IOException){}};
  }
  void SaveFrame(int i){var b=new RenderTargetBitmap((int)ActualWidth,(int)ActualHeight,96,96,PixelFormats.Pbgra32);b.Render(scene);var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(b));using(var f=File.Create(receipt+".frame-"+i+".png"))png.Save(f);}
  public static void Run(string image,string video,string receipt,bool frames,bool live,bool sound,bool waitReady,bool backgroundMain){new Application().Run(new MovieBoot(image,video,receipt,frames,live,sound,waitReady,backgroundMain));}
}
