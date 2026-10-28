using System;
using System.Windows;
using System.Windows.Media.Animation;
public sealed class SakuraCornerAnimation : AnimationTimeline {
 public double From=24,To=20;
 public override Type TargetPropertyType {get{return typeof(CornerRadius);}}
 protected override Freezable CreateInstanceCore(){return new SakuraCornerAnimation{From=From,To=To};}
 public override object GetCurrentValue(object origin,object destination,AnimationClock clock){
  double t=clock.CurrentProgress??0;t=t*t*(3-2*t);
  return new CornerRadius(From+(To-From)*t);
 }
}
