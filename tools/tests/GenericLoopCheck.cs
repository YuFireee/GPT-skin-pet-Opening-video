using System;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
internal static class GenericLoopCheck {
 [STAThread]static int Main(string[] args){
  try{
   if(!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets","generic-opening.flag")))throw new Exception("Generic mode missing");
   var frame=new BitmapImage(new Uri(Path.GetFullPath(args[0])));var loop=new LoadingLoop(frame);loop.Measure(new Size(640,360));loop.Arrange(new Rect(0,0,640,360));
   bool any=false;
   foreach(double time in new[]{.1,.9,2.5}){
    loop.Time=time;loop.InvalidateVisual();loop.UpdateLayout();var bitmap=new RenderTargetBitmap(640,360,96,96,PixelFormats.Pbgra32);bitmap.Render(loop);
    var pixels=new byte[640*360*4];bitmap.CopyPixels(pixels,640*4,0);
    for(int y=130;y<230;y++)for(int x=260;x<380;x++)if(pixels[(y*640+x)*4+3]!=0)throw new Exception("Generic overlay painted the centre of the movie");
    for(int i=3;i<pixels.Length;i+=4)if(pixels[i]>0){any=true;break;}
   }
   if(!any)throw new Exception("No corner animation rendered");return 0;
  }catch(Exception e){Console.Error.WriteLine(e);return 1;}
 }
}
