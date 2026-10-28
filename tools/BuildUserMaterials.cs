// MIT; see ../LICENSE. Converts user-provided artwork; contains no bundled artwork.
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class BuildUserMaterials {
 [DllImport("user32.dll")]static extern bool DestroyIcon(IntPtr icon);
 static string FileAt(string root,string relative){string p=Path.Combine(root,relative.Replace('/',Path.DirectorySeparatorChar));Directory.CreateDirectory(Path.GetDirectoryName(p));return p;}
 static Bitmap Plate(string path){
  using(var source=new Bitmap(path)){
   if(source.Width<512||source.Width>4096||source.Height!=source.Width)throw new ArgumentException("Character PNGs must use the same square canvas, 512..4096 pixels: "+path);
   int transparent=0,visible=0;
   for(int y=0;y<source.Height;y+=8)for(int x=0;x<source.Width;x+=8){if(source.GetPixel(x,y).A<16)transparent++;else visible++;}
   if(visible<50||transparent<visible/9)throw new ArgumentException("Character image must contain a visible character and a real transparent background: "+path);
   var result=new Bitmap(512,512,PixelFormat.Format32bppArgb);
   using(var g=Graphics.FromImage(result)){g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(source,26,26,460,460);}
   return result;
  }
 }
 static void Save(Image image,string root,string relative){image.Save(FileAt(root,relative),ImageFormat.Png);}
 static void Frames(Bitmap open,Bitmap blink,string root,string name,int count,bool thinking){
  var durations=new StringBuilder();
  for(int i=0;i<count;i++){
   bool eyesClosed=i>=18&&i<=20;double phase=2*Math.PI*i/count;
   using(var frame=new Bitmap(512,512,PixelFormat.Format32bppArgb))using(var g=Graphics.FromImage(frame)){
    g.InterpolationMode=InterpolationMode.HighQualityBicubic;
    // Generic whole-character breathing/tilt. No anatomy-specific deformation or inferred layers.
    g.TranslateTransform(256,420+(float)(Math.Sin(phase)*(thinking?1.8:.7)));
    if(thinking)g.RotateTransform((float)(Math.Sin(phase)*1.4));
    g.TranslateTransform(-256,-420);g.DrawImageUnscaled(eyesClosed?blink:open,0,0);
    Save(frame,root,"pet/animations/"+name+"/frames/"+i.ToString("000")+".png");
   }
   durations.AppendLine(i==18||i==20?"40":i==19?"90":thinking?"90":"180");
  }
  System.IO.File.WriteAllText(FileAt(root,"pet/animations/"+name+"/frame-durations.txt"),durations.ToString(),Encoding.ASCII);
 }
 static void Silence(string path){using(var w=new BinaryWriter(System.IO.File.Create(path))){int bytes=2205*2;w.Write(Encoding.ASCII.GetBytes("RIFF"));w.Write(36+bytes);w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));w.Write(16);w.Write((short)1);w.Write((short)1);w.Write(22050);w.Write(44100);w.Write((short)2);w.Write((short)16);w.Write(Encoding.ASCII.GetBytes("data"));w.Write(bytes);w.Write(new byte[bytes]);}}
 public static void Build(string theme,string characters,string output){
  using(var background=new Bitmap(theme)){
   if(background.Width<640||background.Height<360||background.Width>8192||background.Height>8192)throw new ArgumentException("Theme image dimensions must be 640x360 or larger and no side above 8192.");
   Save(background,output,"theme/sakura-calm-soft-portrait.png");
  }
  string[] states={"idle","executing","confirmation"};int canvas=0;
  foreach(string state in states)foreach(string suffix in new[]{"","-blink"})using(var image=new Bitmap(Path.Combine(characters,state+suffix+".png"))){if(canvas==0)canvas=image.Width;if(image.Width!=canvas||image.Height!=canvas)throw new ArgumentException("All six character plates must have identical square dimensions.");}
  for(int i=0;i<states.Length;i++)using(var open=Plate(Path.Combine(characters,states[i]+".png")))using(var closed=Plate(Path.Combine(characters,states[i]+"-blink.png"))){
   if(i==0){
    Save(open,output,"pet/sakura-soft-bust.png");Save(open,output,"pet/gpt-dragon-niang-bust.png");Save(open,output,"pet/upstream-preview.png");
    using(var small=new Bitmap(open,new Size(64,64))){IntPtr handle=small.GetHicon();try{using(var icon=Icon.FromHandle(handle))using(var file=System.IO.File.Create(FileAt(output,"theme/launcher.ico"))){icon.Save(file);}}finally{DestroyIcon(handle);}}
   }
   Frames(open,closed,output,i==0?"soft-portrait-idle-v1":i==1?"soft-portrait-running-v6":"soft-portrait-confirmation-v3",i==1?43:27,i==1);
  }
  Silence(FileAt(output,"pet/press.wav"));Silence(FileAt(output,"pet/release.wav"));
 }
 public static int Main(string[] args){try{if(args.Length!=3)throw new ArgumentException("Expected THEME CHARACTER_DIRECTORY OUTPUT_DIRECTORY");Build(args[0],args[1],args[2]);return 0;}catch(Exception e){Console.Error.WriteLine(e.Message);return 1;}}
}
