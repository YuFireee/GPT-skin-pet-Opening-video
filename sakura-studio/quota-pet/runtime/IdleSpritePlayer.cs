using System;
using System.IO;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
// The animation runs entirely on a typed C# timer, without PowerShell per frame.
public sealed class SakuraIdleSpritePlayer : IDisposable {
 readonly Image image;readonly Window window;readonly ImageSource still;readonly string normalFolder;string folder;string state="normal";
 readonly DispatcherTimer timer;readonly List<BitmapSource> frames=new List<BitmapSource>();
 int[] delays;bool enabled,disposed,faulted;int index;
 public string State {get{return state;}}
 public bool IsPlaying {get{return timer.IsEnabled;}}
 public int CachedFrames {get{return frames.Count;}}
 public int CurrentFrame {get{return index;}}
 public string LastError {get;private set;}
 public bool Faulted {get{return faulted;}}
 public SakuraIdleSpritePlayer(Image target,Window owner,string directory){
  image=target;window=owner;still=image.Source;normalFolder=Path.GetFullPath(directory);folder=normalFolder;
  timer=new DispatcherTimer(DispatcherPriority.Background,window.Dispatcher);timer.Tick+=Tick;
  window.IsVisibleChanged+=Visibility;window.StateChanged+=StateChanged;window.Closed+=Closed;
 }
 public void SetState(string value){
  if(disposed||value==state)return;
  if(value!="normal"&&value!="running"&&value!="confirmation")value="normal";
  state=value;string next=normalFolder;
  if(value!="normal"){
   var candidate=Path.Combine(Path.GetDirectoryName(normalFolder),value=="running"?"executing-soft":"confirmation-soft");
   if(File.Exists(Path.Combine(candidate,"frame-durations.txt")))next=candidate;
  }
  if(next==folder)return;
  Release();folder=next;faulted=false;LastError=null;Synchronize();
  if(timer.IsEnabled){var fade=new System.Windows.Media.Animation.DoubleAnimation(.65,1,TimeSpan.FromMilliseconds(140));image.BeginAnimation(UIElement.OpacityProperty,fade);}
 }
 public void SetEnabled(bool value){if(disposed)return;enabled=value;Synchronize();}
 void Visibility(object sender,DependencyPropertyChangedEventArgs e){Synchronize();}
 void StateChanged(object sender,EventArgs e){Synchronize();}
 void Closed(object sender,EventArgs e){Dispose();}
 void Synchronize(){
  if(disposed)return;
  if(!enabled||!window.IsVisible||window.WindowState==WindowState.Minimized){Release();return;}
  if(faulted||timer.IsEnabled)return;
  try{
   var file=Path.Combine(folder,"frame-durations.txt");if(new FileInfo(file).Length>4096)throw new InvalidDataException();
   var rows=File.ReadAllLines(file);if(rows.Length<2||rows.Length>64)throw new InvalidDataException();
   delays=new int[rows.Length];long decoded=0;
   for(int i=0;i<rows.Length;i++){
    int delay;if(!Int32.TryParse(rows[i],out delay)||delay<30||delay>2000)throw new InvalidDataException();delays[i]=delay;
    string png=Path.Combine(folder,"frames",i.ToString("000")+".png");
    if(new FileInfo(png).Length>2*1024*1024)throw new InvalidDataException();
    var bitmap=new BitmapImage();using(var stream=File.OpenRead(png)){
     bitmap.BeginInit();bitmap.CacheOption=BitmapCacheOption.OnLoad;
     bitmap.DecodePixelWidth=512;bitmap.StreamSource=stream;bitmap.EndInit();
    }
    if(bitmap.PixelWidth>512||bitmap.PixelHeight>512)throw new InvalidDataException();
    decoded+=(long)bitmap.PixelWidth*bitmap.PixelHeight*4;if(decoded>48*1024*1024)throw new InvalidDataException();
    bitmap.Freeze();frames.Add(bitmap);
   }
   index=0;image.Source=frames[0];timer.Interval=TimeSpan.FromMilliseconds(delays[0]);timer.Start();
  }catch(Exception error){LastError=error.Message;faulted=true;Release();}
 }
 void Tick(object sender,EventArgs e){
  if(disposed||!enabled||!window.IsVisible||frames.Count==0){Release();return;}
  index=(index+1)%frames.Count;image.Source=frames[index];timer.Interval=TimeSpan.FromMilliseconds(delays[index]);
 }
 void Release(){timer.Stop();image.BeginAnimation(UIElement.OpacityProperty,null);image.Source=still;frames.Clear();delays=null;index=0;}
 public void Dispose(){if(disposed)return;disposed=true;Release();timer.Tick-=Tick;window.IsVisibleChanged-=Visibility;window.StateChanged-=StateChanged;window.Closed-=Closed;}
}
