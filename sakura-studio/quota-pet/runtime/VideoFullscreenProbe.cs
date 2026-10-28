using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Automation;

// One-shot, isolated accessibility probe. Never run UIA inside the pet process.
// Exit codes: 0 positive web-video controls; 2 no evidence; 3 unavailable.
public static class VideoFullscreenProbe {
 [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 public static bool WebFullscreenNotice(string name) {
  if(String.IsNullOrEmpty(name))return false;
  string text=name.ToLowerInvariant().Replace(" ","");
  return (text.Contains("退出全屏")||text.Contains("exitfullscreen"))&&text.Contains("esc")&&!text.Contains("f11");
 }
 public static bool VideoControl(string name,bool inDocument,bool visible) {
  if(!inDocument||!visible||String.IsNullOrEmpty(name))return false;
  name=name.ToLowerInvariant().Replace(" ","");
  return name.Contains("退出全屏")||name.Contains("退出全螢幕")||name.Contains("exitfullscreen")||name.Contains("leavefullscreen");
 }
 [STAThread] public static int Main(string[] args) {
  try {
   long handle;uint owner;
   if(args.Length!=2||!long.TryParse(args[0],out handle)||!uint.TryParse(args[1],out owner))return 3;
   var hwnd=new IntPtr(handle);uint pid;GetWindowThreadProcessId(hwnd,out pid);
   if(GetForegroundWindow()!=hwnd||pid!=owner)return 3;
   int result=Inspect(hwnd);return GetForegroundWindow()==hwnd?result:3;
  }catch{return 3;}
 }
 public static int Inspect(IntPtr hwnd) {
  try{
   var root=AutomationElement.FromHandle(hwnd);
   var nodes=new Queue<Tuple<AutomationElement,int,bool>>();nodes.Enqueue(Tuple.Create(root,0,false));
   var clock=Stopwatch.StartNew();int count=0;
   var walker=TreeWalker.ControlViewWalker;
   while(nodes.Count>0&&count++<384&&clock.ElapsedMilliseconds<650){
    var node=nodes.Dequeue();var current=node.Item1.Current;
    bool document=node.Item3||current.ControlType==ControlType.Document;
    // Web players commonly expose DIV/SVG controls as Text or Custom, not Button.
    string name=current.Name;
    if(String.IsNullOrEmpty(name))name=current.HelpText;
    if(VideoControl(name,document,!current.IsOffscreen)||(!document&&!current.IsOffscreen&&WebFullscreenNotice(name)))
     return 0;
    if(node.Item2>=24||current.IsOffscreen)continue;
    var child=walker.GetFirstChild(node.Item1);int siblings=0;
    while(child!=null&&siblings++<64&&nodes.Count<384&&clock.ElapsedMilliseconds<650){
     nodes.Enqueue(Tuple.Create(child,node.Item2+1,document));child=walker.GetNextSibling(child);
    }
   }
   return 2;
  }catch{return 3;}
 }
}
