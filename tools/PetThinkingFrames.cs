using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Collections.Generic;
// Reused static arm overlay. The head alone sways slowly around the neck; body stays fixed.
public static class PetThinkingFrames {
 const int Size=512;
 static double Smooth(double x){x=Math.Max(0,Math.Min(1,x));return x*x*(3-2*x);}
 static double Eye(double x,double y,double cx,double cy,double rx,double ry,double angle){
  double c=Math.Cos(angle),s=Math.Sin(angle),dx=x-cx,dy=y-cy;
  double u=(dx*c+dy*s)/rx,v=(-dx*s+dy*c)/ry;
  return 1-Smooth((Math.Sqrt(u*u+v*v)-.90)/.10);
 }
 static double Eyes(double x,double y){return Math.Max(Eye(x,y,.395,.606,.145,.108,-.27),Eye(x,y,.675,.561,.126,.114,-.12));}
 static double Wind(double x,double y){
  double left=Smooth((.44-x)/.19)*Smooth((y-.40)/.46);
  double right=Smooth((x-.71)/.22)*Smooth((y-.36)/.52);
  // Root of the head stays stationary, and a protected centre locks face/clothes.
  double mask=Math.Max(left,right);
  if(y>.745){double centre=1-Smooth((Math.Abs(x-.515)-.13)/.14);mask*=1-centre;}
  double face=Math.Sqrt(Math.Pow((x-.55)/.275,2)+Math.Pow((y-.605)/.205,2));
  mask*=Smooth((face-1)/.13);
  return mask;
 }
 static byte[] Read(string path){
  using(var image=new Bitmap(path))using(var bitmap=new Bitmap(Size,Size,PixelFormat.Format32bppPArgb)){
   using(var g=Graphics.FromImage(bitmap)){g.CompositingMode=CompositingMode.SourceCopy;g.InterpolationMode=InterpolationMode.HighQualityBicubic;g.DrawImage(image,new Rectangle(0,0,Size,Size));}
   var bits=bitmap.LockBits(new Rectangle(0,0,Size,Size),ImageLockMode.ReadOnly,PixelFormat.Format32bppPArgb);
   var data=new byte[Size*Size*4];Marshal.Copy(bits.Scan0,data,0,data.Length);bitmap.UnlockBits(bits);return data;
  }
 }
 static double Sample(byte[] image,double x,double y,int channel){
  if(x<0||y<0||x>=Size-1||y>=Size-1)return 0;
  int ix=(int)x,iy=(int)y;double u=x-ix,v=y-iy;int p=(iy*Size+ix)*4+channel;
  return image[p]*(1-u)*(1-v)+image[p+4]*u*(1-v)+image[p+Size*4]*(1-u)*v+image[p+Size*4+4]*u*v;
 }
 static void Write(byte[] pixels,string path){
  using(var bitmap=new Bitmap(Size,Size,PixelFormat.Format32bppPArgb)){
   var bits=bitmap.LockBits(new Rectangle(0,0,Size,Size),ImageLockMode.WriteOnly,PixelFormat.Format32bppPArgb);Marshal.Copy(pixels,0,bits.Scan0,pixels.Length);bitmap.UnlockBits(bits);bitmap.Save(path,ImageFormat.Png);
  }
 }
 public const double HeadPivotX=268,HeadPivotY=390;
 public struct Pose {public double Yaw,Pitch,Roll;public Pose(double y,double p,double r){Yaw=y;Pitch=p;Roll=r;}}
 static readonly double[] PoseTimes={0,.12,.22,.42,.52,.66,.78,.90,1};
 static readonly Pose[] Poses={new Pose(0,0,0),new Pose(-.18,-.035,-.045),new Pose(-.18,-.035,-.045),new Pose(.20,.04,.050),new Pose(.20,.04,.050),new Pose(.04,-.075,-.025),new Pose(-.05,.045,.025),new Pose(0,0,0),new Pose(0,0,0)};
 public static Pose ThinkingPose(double phase){
  phase=Math.Max(0,Math.Min(1,phase));int i=0;while(i<PoseTimes.Length-2&&phase>PoseTimes[i+1])i++;
  double w=Smooth((phase-PoseTimes[i])/(PoseTimes[i+1]-PoseTimes[i]));var a=Poses[i];var b=Poses[i+1];
  return new Pose(a.Yaw+(b.Yaw-a.Yaw)*w,a.Pitch+(b.Pitch-a.Pitch)*w,a.Roll+(b.Roll-a.Roll)*w);
 }
 static double Depth(double x,double y){return 85*Math.Sqrt(Math.Max(0,1-Math.Pow((x-268)/240,2)-Math.Pow((y-245)/245,2)));}
 public static PointF HeadPoint(double x,double y,double phase){
  var p=ThinkingPose(phase);double depth=Depth(x,y);
  double u=(x-HeadPivotX)*Math.Cos(p.Yaw)+depth*Math.Sin(p.Yaw);
  double v=(y-HeadPivotY)*Math.Cos(p.Pitch)-depth*Math.Sin(p.Pitch);
  return new PointF((float)(HeadPivotX+u*Math.Cos(p.Roll)-v*Math.Sin(p.Roll)),(float)(HeadPivotY+u*Math.Sin(p.Roll)+v*Math.Cos(p.Roll)));
 }
 public static PointF ArmPoint(double x,double y,double phase){return new PointF((float)(x-40),(float)y);}
 public static int Main(string[] args){
  if(args.Length!=4)return 2;
  string folder=Path.GetFullPath(args[3]);Directory.CreateDirectory(folder);
  var open=Read(args[0]);var closed=Read(args[1]);var arm=Read(args[2]);
  var durations=new List<int>();int index=0;long fixedPixels=0,verified=0,armChecks=0,armEqual=0,bodyChecks=0,bodyEqual=0;
  for(int phase=0;phase<40;phase++){
   int variants=phase==28?4:1;
   for(int variant=0;variant<variants;variant++){
    double blink=variant==0?0:1;
    int duration=variant==0?120:variant==2?90:40;
    var pixels=new byte[open.Length];double time=2*Math.PI*phase/40;
    double progress=phase/40.0;
    var pose=ThinkingPose(progress);
    for(int y=0;y<Size;y++)for(int x=0;x<Size;x++){
     double nx=(x+.5)/Size,ny=(y+.5)/Size;
     // Face and jaw move together; blend only below the jaw, around the neck.
     double headWeight=1-Smooth((ny-.765)/.055);
     // Long outer hair follows the head while the shoulder and sleeve remain fixed.
     double side=Math.Max(Smooth((.26-nx)/.08),Smooth((nx-.85)/.09));
     headWeight=Math.Max(headWeight,side);
     double tilt=pose.Roll*headWeight,yaw=pose.Yaw*headWeight,pitch=pose.Pitch*headWeight;
     double hx=x-HeadPivotX,hy=y-HeadPivotY;
     double u=hx*Math.Cos(tilt)+hy*Math.Sin(tilt),v=-hx*Math.Sin(tilt)+hy*Math.Cos(tilt);
     double headX=HeadPivotX+u,headY=HeadPivotY+v;
     // Gentle ellipsoid projection gives facial features parallax as the head turns.
     // Invert the projection; no image crossfade or doubled outlines.
     for(int solve=0;solve<4;solve++){
      double depth=Depth(headX,headY);
      headX=HeadPivotX+(u-depth*Math.Sin(yaw))/Math.Cos(yaw);
      headY=HeadPivotY+(v+depth*Math.Sin(pitch))/Math.Cos(pitch);
     }
     double sourceNX=(headX+.5)/Size,sourceNY=(headY+.5)/Size;
     double weight=Wind(sourceNX,sourceNY),edge=Smooth(Math.Min(sourceNX,1-sourceNX)/.04);
     // Angular strand movement, rooted at the upper side locks. Face/neck are protected.
     double rootX=sourceNX<.5?Size*.24:Size*.81,rootY=Size*.48;
     double angle=(sourceNX<.5?.012:-.014)*Math.Sin(time+(sourceNX<.5?0:-.6))*weight*edge;
     double ribbon=Eye(sourceNX,sourceNY,.145,.575,.135,.195,0);
     if(ribbon>.01){angle+=.018*Math.Sin(time-.35)*ribbon;rootX=Size*.14;rootY=Size*.49;}
     double rx=headX-rootX,ry=headY-rootY;
     double sx=rootX+rx*Math.Cos(angle)+ry*Math.Sin(angle);
     double sy=rootY-rx*Math.Sin(angle)+ry*Math.Cos(angle);
     double eye=Eyes((sx+.5)/Size,(sy+.5)/Size)*blink;
     // Exact old arm coordinates in every frame. No rotation, scale or deformation.
     double ax=x+40,ay=y;
     double alpha=Sample(arm,ax,ay,3)/255.0;
     int offset=(y*Size+x)*4;
     for(int c=0;c<4;c++){
      double basePixel=Math.Abs(angle)<1e-12&&Math.Abs(tilt)+Math.Abs(yaw)+Math.Abs(pitch)<1e-12?open[offset+c]:Sample(open,sx,sy,c);
      double background=basePixel*(1-eye)+Sample(closed,sx,sy,c)*eye;
      double value=Sample(arm,ax,ay,c)+background*(1-alpha);
      pixels[offset+c]=(byte)Math.Max(0,Math.Min(255,Math.Round(value)));
      if(Math.Abs(angle)<1e-12&&Math.Abs(tilt)+Math.Abs(yaw)+Math.Abs(pitch)<1e-12&&eye<1e-12&&alpha==0){verified++;if(pixels[offset+c]==open[offset+c])fixedPixels++;}
      if(alpha==1){armChecks++;if(pixels[offset+c]==arm[((int)ay*Size+(int)ax)*4+c])armEqual++;}
      if(nx>.46&&nx<.70&&ny>.86&&alpha==0){bodyChecks++;if(pixels[offset+c]==open[offset+c])bodyEqual++;}
     }
    }
    Write(pixels,Path.Combine(folder,index.ToString("000")+".png"));durations.Add(duration);index++;
   }
  }
  Write(open,Path.Combine(folder,"reference.png"));
  File.WriteAllText(Path.Combine(folder,"timing.json"),"{\"width\":512,\"height\":512,\"durationsMs\":["+String.Join(",",durations)+"],\"fixedChannelChecks\":"+verified+",\"fixedChannelsEqual\":"+fixedPixels+",\"staticArmChannelChecks\":"+armChecks+",\"staticArmChannelsEqual\":"+armEqual+",\"bodyChannelChecks\":"+bodyChecks+",\"bodyChannelsEqual\":"+bodyEqual+",\"motion\":\"yaw-pitch-roll-with-holds\",\"frames\":43}");
  Console.WriteLine("Frames="+index+"; fixed pixels="+(fixedPixels==verified)+"; static arm="+(armChecks==armEqual)+"; body fixed="+(bodyChecks==bodyEqual));
  return fixedPixels==verified&&armEqual==armChecks&&armChecks>0&&bodyChecks==bodyEqual?0:3;
 }
}
