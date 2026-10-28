using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

internal sealed class BootHandoff : IDisposable {
  [StructLayout(LayoutKind.Sequential)] internal struct Rect {public int Left,Top,Right,Bottom;}
  [StructLayout(LayoutKind.Sequential)] struct Point {public int X,Y;}
  [StructLayout(LayoutKind.Sequential)] struct Properties {
    public uint Flags;public Rect Destination,Source;public byte Opacity;
    [MarshalAs(UnmanagedType.Bool)] public bool Visible;
    [MarshalAs(UnmanagedType.Bool)] public bool ClientOnly;
  }
  [DllImport("dwmapi.dll")] static extern int DwmRegisterThumbnail(IntPtr destination,IntPtr source,out IntPtr thumbnail);
  [DllImport("dwmapi.dll")] static extern int DwmUpdateThumbnailProperties(IntPtr thumbnail,ref Properties properties);
  [DllImport("dwmapi.dll")] static extern int DwmUnregisterThumbnail(IntPtr thumbnail);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr window,out Rect rect);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr window,ref Point point);
  [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window,int command);
  IntPtr heldSource;
  uint heldPid;
  public bool BackgroundHeld {get{return heldSource!=IntPtr.Zero&&IsIconic(heldSource);}}
  public bool SourceAvailable(string file){
    try{
      if(!File.Exists(file))return false;
      string[] fields=File.ReadAllText(file).Trim().Split(' ');long h;uint expected,actual;
      if(fields.Length!=2||!Int64.TryParse(fields[0],out h)||!UInt32.TryParse(fields[1],out expected)||h==0||expected==0)return false;
      var candidate=new IntPtr(h);GetWindowThreadProcessId(candidate,out actual);
      return actual==expected&&IsWindowVisible(candidate);
    }catch(IOException){return false;}
  }
  public void HoldSource(string file){
    try{
      if(File.Exists(file)){
        string[] fields=File.ReadAllText(file).Trim().Split(' ');long h;uint expected,actual;
        if(fields.Length!=2||!Int64.TryParse(fields[0],out h)||!UInt32.TryParse(fields[1],out expected)||h==0||expected==0)return;
        var candidate=new IntPtr(h);GetWindowThreadProcessId(candidate,out actual);
        Rect r;if(actual!=expected||!IsWindowVisible(candidate)||(!IsIconic(candidate)&&(!GetClientRect(candidate,out r)||r.Right<300||r.Bottom<200)))return;
        if(heldSource!=IntPtr.Zero&&(heldSource!=candidate||heldPid!=expected))ReleaseSource();
        heldSource=candidate;heldPid=expected;
      }
      uint pid;GetWindowThreadProcessId(heldSource,out pid);
      if(heldSource!=IntPtr.Zero&&pid==heldPid&&IsWindowVisible(heldSource)&&!IsIconic(heldSource))ShowWindowAsync(heldSource,7);
    }catch(IOException){}
  }
  public void ReleaseSource(){
    uint pid;GetWindowThreadProcessId(heldSource,out pid);
    // Restore only a visible, minimized window whose ownership was verified before holding it.
    if(heldSource!=IntPtr.Zero&&pid==heldPid&&IsWindowVisible(heldSource)&&IsIconic(heldSource))ShowWindowAsync(heldSource,9);
    heldSource=IntPtr.Zero;
  }
  IntPtr source,thumbnail;
  uint processId;
  public bool Live {get{return thumbnail!=IntPtr.Zero;}}
  public bool Failed {get;private set;}
  public bool Connect(Window destination,string file){
    if(!File.Exists(file))return false;
    try{
      string[] fields=File.ReadAllText(file).Trim().Split(' ');long handle;uint pid;
      if(fields.Length!=2||!Int64.TryParse(fields[0],out handle)||!UInt32.TryParse(fields[1],out pid)||handle==0||pid==0)return false;
      var next=new IntPtr(handle);
      if(source!=next||processId!=pid){Dispose();Failed=false;}
      else if(Live&&Valid())return true;
      else if(Live)Dispose();
      source=next;processId=pid;if(!Valid()||Failed)return false;
      if(DwmRegisterThumbnail(new WindowInteropHelper(destination).Handle,source,out thumbnail)!=0){Failed=true;thumbnail=IntPtr.Zero;}
      return Live;
    }catch(IOException){return false;}
  }
  public bool Valid(){uint pid;GetWindowThreadProcessId(source,out pid);Rect rect;return pid==processId&&IsWindowVisible(source)&&!IsIconic(source)&&GetClientRect(source,out rect)&&rect.Right>=300&&rect.Bottom>=200;}
  public System.Windows.Rect Bounds(Window destination){
    Rect rect;Point point=new Point();if(!Valid()||!GetClientRect(source,out rect)||!ClientToScreen(source,ref point))return System.Windows.Rect.Empty;
    var visual=PresentationSource.FromVisual(destination);if(visual==null)return System.Windows.Rect.Empty;
    var matrix=visual.CompositionTarget.TransformFromDevice;
    var position=matrix.Transform(new System.Windows.Point(point.X,point.Y));var size=matrix.Transform(new System.Windows.Point(rect.Right,rect.Bottom));
    return new System.Windows.Rect(position.X,position.Y,size.X,size.Y);
  }
  public System.Windows.Rect TargetBounds(Window destination,string file){
    // Geometry is safe to read while the verified source is hidden; DWM still requires Valid().
    try{
      if(!File.Exists(file))return System.Windows.Rect.Empty;
      var fields=File.ReadAllText(file).Trim().Split(' ');long handle;uint expected,pid;Rect rect;Point point=new Point();
      if(fields.Length!=2||!Int64.TryParse(fields[0],out handle)||!UInt32.TryParse(fields[1],out expected)||handle==0||expected==0)return System.Windows.Rect.Empty;
      var target=new IntPtr(handle);GetWindowThreadProcessId(target,out pid);
      if(pid!=expected||IsIconic(target)||!GetClientRect(target,out rect)||rect.Right<300||rect.Bottom<200||!ClientToScreen(target,ref point))return System.Windows.Rect.Empty;
      var visual=PresentationSource.FromVisual(destination);if(visual==null)return System.Windows.Rect.Empty;
      var matrix=visual.CompositionTarget.TransformFromDevice;
      var position=matrix.Transform(new System.Windows.Point(point.X,point.Y));var size=matrix.Transform(new System.Windows.Point(rect.Right,rect.Bottom));
      return new System.Windows.Rect(position.X,position.Y,size.X,size.Y);
    }catch(IOException){return System.Windows.Rect.Empty;}
  }
  public bool Draw(Window destination,double x,double y,double width,double height,double opacity){
    if(!Live||!Valid()){Dispose();return false;}
    var transform=PresentationSource.FromVisual(destination).CompositionTarget.TransformToDevice;
    var a=transform.Transform(new System.Windows.Point(x,y));var b=transform.Transform(new System.Windows.Point(x+width,y+height));
    var properties=new Properties{Flags=1|4|8|16,Destination=new Rect{Left=(int)a.X,Top=(int)a.Y,Right=(int)b.X,Bottom=(int)b.Y},Opacity=(byte)(255*Math.Max(0,Math.Min(1,opacity))),Visible=true,ClientOnly=true};
    if(DwmUpdateThumbnailProperties(thumbnail,ref properties)!=0){Failed=true;Dispose();return false;}return true;
  }
  public void Dispose(){if(thumbnail!=IntPtr.Zero){DwmUnregisterThumbnail(thumbnail);thumbnail=IntPtr.Zero;}}
}
