using System;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

// Draw only the waiting animation; the supplied movie's last frame stays untouched below it.
internal sealed class LoadingLoop : FrameworkElement {
  readonly bool genericOpening=System.IO.File.Exists(System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets","generic-opening.flag"));
  readonly double width,height;
  readonly ImageBrush logoMask;
  readonly Rect logoBounds;
  readonly PathGeometry arm;
  const int PathSamples=256;
  readonly Point[][] outerPoints=new Point[6][];
  readonly Pen[] outerPens,innerPens;
  readonly Brush petalBrush;
  static readonly Point[] innerVertices={new Point(.50,.335),new Point(.64,.415),new Point(.64,.585),new Point(.50,.665),new Point(.36,.585),new Point(.36,.415)};
  readonly Geometry petal=Geometry.Parse("M0,-6 C6,-9 9,-1 1,7 C-6,5 -8,-2 0,-6 Z");
  public double Time {get;set;}
  public double EntryOpacity {get{double p=Math.Max(0,Math.Min(1,Time/.65));return p*p*(3-2*p);}}
  public LoadingLoop(BitmapSource frame){
    IsHitTestVisible=false;width=frame.PixelWidth;height=frame.PixelHeight;
    petal.Freeze();var petals=new SolidColorBrush(Color.FromRgb(246,178,220));petals.Freeze();petalBrush=petals;
    // A user's arbitrary movie has no known knot geometry. Keep its final frame intact.
    if(genericOpening)return;
    var rgba=new FormatConvertedBitmap(frame,PixelFormats.Bgra32,null,0);int w=frame.PixelWidth,h=frame.PixelHeight,stride=w*4;
    byte[] pixels=new byte[h*stride],mask=new byte[h*stride];rgba.CopyPixels(pixels,stride,0);
    int minX=w,maxX=0,minY=h,maxY=0;
    for(int y=(int)(h*.15);y<h*.85;y++)for(int x=(int)(w*.27);x<w*.73;x++){
      int i=y*stride+x*4;int low=Math.Min(pixels[i],Math.Min(pixels[i+1],pixels[i+2]));int high=Math.Max(pixels[i],Math.Max(pixels[i+1],pixels[i+2]));
      if(low<190||high-low>45)continue;byte alpha=(byte)Math.Min(255,(low-190)*5);mask[i]=mask[i+1]=mask[i+2]=255;mask[i+3]=alpha;
      if(alpha>180){minX=Math.Min(minX,x);maxX=Math.Max(maxX,x);minY=Math.Min(minY,y);maxY=Math.Max(maxY,y);}
    }
    logoBounds=maxX>minX?new Rect(minX,minY,maxX-minX,maxY-minY):new Rect(w*.35,h*.24,w*.3,h*.54);
    var bitmap=BitmapSource.Create(w,h,96,96,PixelFormats.Bgra32,null,mask,stride);bitmap.Freeze();
    logoMask=new ImageBrush(bitmap){ViewportUnits=BrushMappingMode.Absolute,Viewport=new Rect(0,0,w,h),ViewboxUnits=BrushMappingMode.Absolute,Viewbox=new Rect(0,0,w,h),Stretch=Stretch.Fill};logoMask.Freeze();
    arm=PathGeometry.CreateFromGeometry(Geometry.Parse("M290,343 L290,242 Q290,232 299,227 L394,172 C449,139 550,177 552,250 Q553,269 549,287"));arm.Freeze();
    outerPens=CreatePens(240);innerPens=CreatePens(250);
    for(int i=0;i<6;i++){outerPoints[i]=new Point[PathSamples+1];for(int j=0;j<=PathSamples;j++)outerPoints[i][j]=LogoPoint((double)j/PathSamples,i*Math.PI/3);}
  }
  Pen[] CreatePens(int peak){
    var pens=new Pen[71];for(int j=0;j<pens.Length;j++){
      var brush=new SolidColorBrush(Color.FromArgb((byte)(peak*Math.Pow(1-j/71.0,.65)),255,119,194));brush.Freeze();
      var pen=new Pen(brush,logoBounds.Width*.052*.90){StartLineCap=PenLineCap.Round,EndLineCap=PenLineCap.Round};pen.Freeze();pens[j]=pen;
    }return pens;
  }
  protected override void OnRender(DrawingContext dc){
    base.OnRender(dc);double scale=Math.Min(ActualWidth/width,ActualHeight/height);if(scale<=0)return;
    dc.PushClip(new RectangleGeometry(new Rect(0,0,ActualWidth,ActualHeight)));
    dc.PushTransform(new TranslateTransform((ActualWidth-width*scale)/2,(ActualHeight-height*scale)/2));dc.PushTransform(new ScaleTransform(scale,scale));
    dc.PushOpacity(EntryOpacity);DrawCorners(dc);
    if(!genericOpening){
    dc.PushOpacityMask(logoMask);
    for(int i=0;i<6;i++){
      double phase=(Time/.8+i/6.0)%1;
      for(int j=70;j>=0;j--){double f=(phase-j*.01+1)%1,next=f+.01;if(next>1)continue;
        dc.DrawLine(outerPens[j],SamplePoint(i,f),SamplePoint(i,next));
      }
    }
    DrawInnerLoop(dc);
    dc.Pop();
    }
    dc.Pop();dc.Pop();dc.Pop();dc.Pop();
  }
  // Clockwise around the inner hexagon, independent of the six outer strands.
  void DrawInnerLoop(DrawingContext dc){
    double phase=(Time/.5)%1;
    for(int j=70;j>=0;j--){
      double f=(phase-j*.01+1)%1,next=f+.01;if(next>1)continue;
      dc.DrawLine(innerPens[j],InnerPoint(f),InnerPoint(next));
    }
  }
  Point InnerPoint(double fraction){
    double segment=fraction*6;int index=Math.Min(5,(int)segment);double t=segment-index;
    Point a=innerVertices[index],b=innerVertices[(index+1)%6];
    return new Point(logoBounds.Left+(a.X+(b.X-a.X)*t)*logoBounds.Width,logoBounds.Top+(a.Y+(b.Y-a.Y)*t)*logoBounds.Height);
  }
  Point SamplePoint(int armIndex,double fraction){
    double at=fraction*PathSamples;int i=Math.Min(PathSamples-1,(int)at);double t=at-i;
    Point a=outerPoints[armIndex][i],b=outerPoints[armIndex][i+1];return new Point(a.X+(b.X-a.X)*t,a.Y+(b.Y-a.Y)*t);
  }
  Point LogoPoint(double fraction,double angle){
    Point p,tangent;arm.GetPointAtFractionLength(fraction,out p,out tangent);
    double px=p.X-360.626,py=p.Y-360.626;
    double x=px*Math.Cos(angle)-py*Math.Sin(angle)+360.626,y=px*Math.Sin(angle)+py*Math.Cos(angle)+360.626;
    return new Point(logoBounds.Left+(x-118.557)/484.139*logoBounds.Width,logoBounds.Top+(y-120.758)/479.818*logoBounds.Height);
  }
  void DrawCorners(DrawingContext dc){
    for(int corner=0;corner<4;corner++)for(int wave=0;wave<3;wave++){
      double p=(Time/(5.4+corner*.45)+wave/3.0+corner*.11)%1;
      double alpha=Math.Pow(Math.Sin(Math.PI*p),1.7)*.40,r=(25+p*220)*width/1344;
      for(int k=0;k<5;k++){
        double a=(15+k*15)*Math.PI/180,x=Math.Cos(a)*r,y=Math.Sin(a)*r;
        if(corner%2==1)x=width-x;if(corner>=2)y=height-y;
        x+=Math.Sin(Time*.9+k)*3;y+=Math.Cos(Time*.8+k)*3;
        double s=(.65+(k%3)*.15)*width/1344,rotation=(k*28+Time*13+corner*55)*Math.PI/180;
        var transform=new MatrixTransform(new Matrix(s*Math.Cos(rotation),s*Math.Sin(rotation),-s*Math.Sin(rotation),s*Math.Cos(rotation),x,y));transform.Freeze();
        dc.PushOpacity(alpha);dc.PushTransform(transform);
        dc.DrawGeometry(petalBrush,null,petal);dc.Pop();dc.Pop();
      }
    }
  }
}
