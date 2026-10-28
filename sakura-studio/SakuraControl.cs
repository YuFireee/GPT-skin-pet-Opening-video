using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

internal sealed class StudioApi {
 readonly string origin,root;string token;
 readonly JavaScriptSerializer json=new JavaScriptSerializer();
 public StudioApi(string directory,int port){root=directory;origin="http://127.0.0.1:"+port+"/";}
 public static Dictionary<string,object> Map(object value){return value as Dictionary<string,object>??new Dictionary<string,object>();}
 public static object Get(Dictionary<string,object> map,string key){object v;return map.TryGetValue(key,out v)?v:null;}
 public static bool Flag(Dictionary<string,object> map,string key){return Object.Equals(Get(map,key),true);}
 public static string Text(Dictionary<string,object> map,string key){return Convert.ToString(Get(map,key));}
 async Task<string> Request(string path,object payload){
  using(var client=new WebClient()){
   client.Proxy=null;client.Encoding=Encoding.UTF8;
   if(token!=null)client.Headers["X-Sakura-Token"]=token;
   client.Headers[HttpRequestHeader.ContentType]="application/json";
   using(var deadline=new System.Threading.Timer(_=>client.CancelAsync(),null,30000,System.Threading.Timeout.Infinite)){
    try{return payload==null?await client.DownloadStringTaskAsync(origin+path):await client.UploadStringTaskAsync(origin+path,"POST",json.Serialize(payload));}
    catch(WebException e){
     if(e.Response!=null){using(var response=e.Response)using(var reader=new StreamReader(response.GetResponseStream(),Encoding.UTF8)){
      try{var body=Map(json.DeserializeObject(reader.ReadToEnd()));throw new InvalidOperationException(Text(body,"error"),e);}catch(InvalidOperationException){throw;}catch{}
     }}throw new InvalidOperationException("无法连接本地后台，请从樱色工坊入口重新打开。",e);
    }
   }
  }
 }
 async Task Connect(){
  if(token!=null)return;
  var health=Map(json.DeserializeObject(await Request("health",null)));
  string id;using(var sha=SHA256.Create()){id=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(root.ToLowerInvariant()))).Replace("-","").ToLowerInvariant();}
  if(Text(health,"service")!="sakura-studio"||Text(health,"installationId")!=id)throw new InvalidOperationException("本地端口属于另一份安装，未接管。请从原目录打开控制窗口。");
  var match=Regex.Match(await Request("",null),"name=\"sakura-token\" content=\"([^\"]+)\"");
  if(!match.Success)throw new InvalidOperationException("本地会话验证失败，请重新打开工具。");token=match.Groups[1].Value;
 }
 public async Task<Dictionary<string,object>> Call(string route,object payload=null){await Connect();return Map(json.DeserializeObject(await Request("api/"+route,payload)));}
}

internal sealed class StudioWindow:Form {
 readonly NativeStudioContext owner;readonly Label status=new Label();
 readonly Font bodyFont=new Font("Microsoft YaHei UI",9),headingFont=new Font("Microsoft YaHei UI",14,FontStyle.Bold);
 readonly Dictionary<string,TrackBar> sliders=new Dictionary<string,TrackBar>();
 readonly Dictionary<string,CheckBox> toggles=new Dictionary<string,CheckBox>();
 readonly List<Button> actions=new List<Button>();bool loaded;
 readonly PictureBox preview=new PictureBox();Image previewImage;
 internal bool HasPreview {get{return previewImage!=null;}}
 public StudioWindow(NativeStudioContext context){
  owner=context;Text="樱色工坊";Name="SakuraControlWindow";ClientSize=new Size(570,680);MinimumSize=new Size(530,540);
  StartPosition=FormStartPosition.CenterScreen;Font=bodyFont;BackColor=Color.FromArgb(250,247,252);
  var layout=new TableLayoutPanel{Dock=DockStyle.Fill,RowCount=3,Padding=new Padding(18),ColumnCount=1};layout.RowStyles.Add(new RowStyle(SizeType.Absolute,42));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,72));Controls.Add(layout);
  layout.Controls.Add(new Label{Text="樱色工坊  ·  轻量控制窗口",AutoSize=true,Font=headingFont},0,0);
  var tabs=new TabControl{Dock=DockStyle.Fill};layout.Controls.Add(tabs,0,1);
  var home=Page(tabs,"工作空间");home.Name="home";home.FlowDirection=FlowDirection.LeftToRight;home.WrapContents=true;home.Controls.Add(new Label{Text="关闭此窗口后，仍可通过托盘管理桌宠。",Width=470,Height=40,Margin=new Padding(8,14,8,6)});
  preview.Size=new Size(460,160);preview.SizeMode=PictureBoxSizeMode.Zoom;preview.BackColor=Color.FromArgb(237,229,240);preview.Margin=new Padding(5,0,5,10);preview.AccessibleName="主题静态预览";
  var previewPath=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets","sakura-control-preview.jpg");
  try{using(var file=File.OpenRead(previewPath))using(var decoded=Image.FromStream(file)){previewImage=new Bitmap(decoded);}preview.Image=previewImage;home.Controls.Add(preview);}
  catch(Exception e){if(!(e is IOException||e is ArgumentException||e is OutOfMemoryException||e is UnauthorizedAccessException))throw;home.Controls.Add(new Label{Text="静态预览暂不可用，其他功能仍可正常使用。",Width=460,Height=30,Margin=new Padding(5)});}
  Action(home,"开启桌宠",()=>owner.Pet(true));Action(home,"关闭桌宠",()=>owner.Pet(false));
  Action(home,"一键启动工作空间",async()=>{await owner.Save(this);await owner.Execute("workspace/start",new {});});
  Action(home,"取消后续启动步骤",()=>owner.Execute("workspace/cancel",new {}));
  Action(home,"启动并自动换肤",()=>owner.Execute("launch",new {}));Action(home,"显示已换肤窗口",()=>owner.Execute("show",new {}));
  Action(home,"刷新状态",()=>owner.Refresh());Action(home,"检查桌面连接",()=>owner.Inspect());
  Action(home,"修复无响应窗口",async()=>{if(MessageBox.Show(this,"将重新打开专用换肤窗口，请先保存其中未发送的内容。","修复窗口",MessageBoxButtons.OKCancel,MessageBoxIcon.Question)==DialogResult.OK)await owner.Execute("repair",new {confirmRestart=true});});
  var theme=Page(tabs,"主题设置");Toggle(theme,"motion","动态阳光与樱花背景");
  AddSlider(theme,"menubar","顶部菜单栏");AddSlider(theme,"rail","最左图标栏");AddSlider(theme,"sidebar","侧边栏");AddSlider(theme,"header","上边栏");AddSlider(theme,"message","对话面板");AddSlider(theme,"composer","输入框");
  Action(theme,"保存设置",()=>owner.Save(this));Action(theme,"保存并应用主题",async()=>{await owner.Save(this);await owner.Execute("apply",new {});});Action(theme,"恢复原有外观",()=>owner.Execute("restore",new {}));
  var pet=Page(tabs,"额度桌宠");pet.Controls.Add(new Label{Text="当前主题角色\n常态、执行与待确认动画已接入。\n左圆环：5小时；右圆环：每周。\n点圆环查看额度，点角色显示台词。\n角色右键可调整大小、位置和动画。",AutoSize=true,Margin=new Padding(8,14,8,16)});
  Toggle(pet,"companion","一键启动时显示桌宠");Action(pet,"开启桌宠",()=>owner.Pet(true));Action(pet,"关闭桌宠",()=>owner.Pet(false));Action(pet,"保存设置",()=>owner.Save(this));
  var boot=Page(tabs,"启动动画");Toggle(boot,"boot","一键启动时播放开场");Toggle(boot,"bootSound","播放开场声音");Action(boot,"保存设置",()=>owner.Save(this));Action(boot,"预览启动动画",()=>owner.Execute("boot-preview",new {}));
  status.Dock=DockStyle.Fill;status.Text="正在读取本地设置…";status.AutoEllipsis=true;status.ForeColor=Color.FromArgb(99,73,113);layout.Controls.Add(status,0,2);
  FormClosed+=(s,e)=>owner.WindowClosed(this);
 }
 protected override void Dispose(bool disposing){if(disposing){preview.Image=null;if(previewImage!=null){previewImage.Dispose();previewImage=null;}preview.Dispose();}base.Dispose(disposing);if(disposing){bodyFont.Dispose();headingFont.Dispose();}}
 FlowLayoutPanel Page(TabControl tabs,string title){var page=new TabPage(title);var panel=new FlowLayoutPanel{Dock=DockStyle.Fill,AutoScroll=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,Padding=new Padding(8)};page.Controls.Add(panel);tabs.TabPages.Add(page);return panel;}
 void Action(FlowLayoutPanel panel,string text,Func<Task> work){var b=new Button{Text=text,AutoSize=true,MinimumSize=new Size(panel.Name=="home"?220:180,34),Margin=new Padding(5)};actions.Add(b);b.Click+=async(s,e)=>await owner.Run(work);panel.Controls.Add(b);}
 void Toggle(FlowLayoutPanel panel,string key,string text){var c=new CheckBox{Text=text,AutoSize=true,Margin=new Padding(8,12,8,8),Enabled=false};toggles.Add(key,c);panel.Controls.Add(c);}
 void AddSlider(FlowLayoutPanel panel,string key,string text){var row=new FlowLayoutPanel{Width=470,Height=43,WrapContents=false};var label=new Label{Text=text,Width=104,Margin=new Padding(3,9,0,0)};var value=new Label{Width=43,Margin=new Padding(2,9,0,0)};var slider=new TrackBar{Minimum=0,Maximum=85,Width=285,Height=36,TickStyle=TickStyle.None,Enabled=false};sliders.Add(key,slider);slider.ValueChanged+=(s,e)=>value.Text=slider.Value+"%";row.Controls.Add(label);row.Controls.Add(slider);row.Controls.Add(value);panel.Controls.Add(row);}
 public void LoadSettings(Dictionary<string,object> settings){if(loaded)return;foreach(var pair in sliders){pair.Value.Value=Math.Max(0,Math.Min(85,Convert.ToInt32(StudioApi.Get(settings,pair.Key))));pair.Value.Enabled=true;}foreach(var pair in toggles){pair.Value.Checked=StudioApi.Flag(settings,pair.Key);pair.Value.Enabled=true;}loaded=true;}
 public Dictionary<string,object> Settings(){if(!loaded)throw new InvalidOperationException("设置尚未加载，请先刷新连接。");var result=new Dictionary<string,object>{{"themeId","sakura-calm-soft-portrait"},{"petId","sakura-calm-soft-portrait"}};foreach(var pair in sliders)result[pair.Key]=pair.Value.Value;foreach(var pair in toggles)result[pair.Key]=pair.Value.Checked;return result;}
 public void Message(string text){if(!IsDisposed)status.Text=text;}
 public void Busy(bool busy){foreach(var b in actions)b.Enabled=!busy;}
}

internal sealed class NativeStudioContext:ApplicationContext {
 [DllImport("user32.dll")]static extern bool ShowWindowAsync(IntPtr handle,int command);
 [DllImport("user32.dll")]static extern bool IsWindowVisible(IntPtr handle);
 [DllImport("user32.dll")]static extern int GetGuiResources(IntPtr process,int flags);
 readonly StudioApi api;readonly NotifyIcon tray;readonly Control dispatcher=new Control();readonly System.Windows.Forms.Timer poll=new System.Windows.Forms.Timer();
 readonly ToolStripMenuItem petOn=new ToolStripMenuItem("开启桌宠"),petOff=new ToolStripMenuItem("关闭桌宠");
 readonly EventWaitHandle showSignal;RegisteredWaitHandle wait;Process parent;StudioWindow window;bool busy,exiting;Dictionary<string,object> snapshot;
 public NativeStudioContext(string root,int port,EventWaitHandle signal,int parentPid){
  api=new StudioApi(root,port);dispatcher.CreateControl();var dispatcherHandle=dispatcher.Handle;showSignal=signal;
  Icon icon;try{icon=new Icon(Path.Combine(root,"assets","launcher.ico"));}catch{icon=(Icon)SystemIcons.Application.Clone();}
  tray=new NotifyIcon{Icon=icon,Text="樱色工坊",Visible=true};var menu=new ContextMenuStrip();tray.ContextMenuStrip=menu;
  menu.Items.Add("打开控制窗口",null,(s,e)=>ShowWindow());menu.Items.Add("关闭控制窗口",null,(s,e)=>CloseWindow());menu.Items.Add(new ToolStripSeparator());menu.Items.Add(petOn);menu.Items.Add(petOff);
  petOn.Click+=async(s,e)=>await Run(()=>Pet(true));petOff.Click+=async(s,e)=>await Run(()=>Pet(false));
  menu.Items.Add(new ToolStripSeparator());menu.Items.Add("一键启动工作空间",null,async(s,e)=>await Run(()=>Execute("workspace/start",new {})));
  menu.Items.Add("退出樱色工坊",null,async(s,e)=>await Run(async()=>{await api.Call("quit",new {});ExitThread();}));
  menu.Opening+=async(s,e)=>{if(!busy)await Run(()=>Refresh());};tray.DoubleClick+=(s,e)=>ShowWindow();
  poll.Interval=5000;poll.Tick+=async(s,e)=>{if(window!=null&&!busy)await Run(()=>Refresh());};
  if(signal!=null)wait=ThreadPool.RegisterWaitForSingleObject(signal,(s,t)=>Post(ShowWindow),null,Timeout.Infinite,false);
  if(parentPid>0){try{parent=Process.GetProcessById(parentPid);parent.EnableRaisingEvents=true;parent.Exited+=(s,e)=>Post(ExitThread);if(parent.HasExited)Post(ExitThread);}catch{Post(ExitThread);}}
 }
 void Post(Action action){if(!exiting&&!dispatcher.IsDisposed){try{dispatcher.BeginInvoke(action);}catch(InvalidOperationException){}}}
 public void ShowWindow(){if(exiting)return;if(window==null){window=new StudioWindow(this);window.Show();poll.Start();var ignored=Run(()=>Refresh());}else{window.WindowState=FormWindowState.Normal;window.Show();window.Activate();}ShowWindowAsync(window.Handle,9);window.BringToFront();window.Activate();}
 public void CloseWindow(){if(window!=null)window.Close();}
 public void WindowClosed(StudioWindow closed){if(window==closed){poll.Stop();window=null;}}
 public async Task Run(Func<Task> work){if(busy)return;busy=true;if(window!=null)window.Busy(true);petOn.Enabled=petOff.Enabled=false;try{await work();}catch(Exception e){poll.Stop();if(window!=null)window.Message(e.Message);else{tray.BalloonTipTitle="樱色工坊";tray.BalloonTipText=e.Message.Length>220?e.Message.Substring(0,220):e.Message;tray.ShowBalloonTip(4000);}}finally{busy=false;if(window!=null)window.Busy(false);UpdateMenu();}}
 void UpdateMenu(){bool running=snapshot!=null&&StudioApi.Flag(snapshot,"companionRunning");petOn.Enabled=!busy&&!running;petOff.Enabled=!busy&&running;}
 public async Task Refresh(){snapshot=await api.Call("control-state");UpdateMenu();if(window!=null){window.LoadSettings(StudioApi.Map(StudioApi.Get(snapshot,"settings")));var auto=StudioApi.Map(StudioApi.Get(snapshot,"autoTheme"));window.Message((StudioApi.Flag(snapshot,"companionRunning")?(StudioApi.Flag(StudioApi.Map(StudioApi.Get(snapshot,"companionDisplay")),"waiting")?"桌宠等待可见主窗口（跟随模式）":"桌宠已显示"):"桌宠已关闭")+" · "+(StudioApi.Flag(auto,"enabled")?"自动换肤已开启":"自动换肤未开启")+"\n"+StudioApi.Text(snapshot,"companionIssue"));}}
 public async Task Pet(bool enabled){await api.Call("companion",new {enabled=enabled});await Refresh();}
 public async Task Save(StudioWindow source){await api.Call("settings",source.Settings());if(window!=null)window.Message("设置已保存。");}
 public async Task Execute(string route,object data){if(route=="workspace/cancel"){var current=await api.Call("control-state");data=new {id=StudioApi.Text(StudioApi.Map(StudioApi.Get(current,"workspace")),"id")};}var result=await api.Call(route,data);await Refresh();if(window!=null)window.Message(StudioApi.Text(result,"message")+((route=="workspace/start")?"工作空间正在启动，可在此窗口关闭后继续执行。":""));}
 public async Task Inspect(){var result=await api.Call("status");if(window!=null)window.Message(StudioApi.Text(StudioApi.Map(StudioApi.Get(result,"connection")),"reason"));}
 protected override void ExitThreadCore(){if(exiting)return;exiting=true;poll.Stop();if(wait!=null)wait.Unregister(null);if(window!=null){window.Close();window=null;}poll.Dispose();tray.Visible=false;var icon=tray.Icon;tray.ContextMenuStrip.Dispose();tray.Dispose();icon.Dispose();if(parent!=null)parent.Dispose();dispatcher.Dispose();base.ExitThreadCore();}
 // Explicit isolated fixture only: no periodic hidden requests and no application launch.
 public async Task Smoke(string receipt){
  try{
   await Refresh();ShowWindow();await Task.Delay(300);
   if(!IsWindowVisible(window.Handle))throw new InvalidOperationException("Control window did not become visible");
   CloseWindow();showSignal.Set();await Task.Delay(200);
   if(window==null||!IsWindowVisible(window.Handle))throw new InvalidOperationException("Hidden tray could not show its control window");
   bool previewLoaded=window.HasPreview;var previewPath=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets","sakura-control-preview.jpg");
   if(File.Exists(previewPath)&&!previewLoaded)throw new InvalidOperationException("Static preview was not decoded");
   if(previewLoaded)using(var unlocked=new FileStream(previewPath,FileMode.Open,FileAccess.Read,FileShare.None)){}
   using(var picture=new Bitmap(window.Width,window.Height)){window.DrawToBitmap(picture,new Rectangle(0,0,picture.Width,picture.Height));picture.Save(receipt+".png",System.Drawing.Imaging.ImageFormat.Png);}

   CloseWindow();GC.Collect();GC.WaitForPendingFinalizers();long cycleBefore=GC.GetTotalMemory(true);int gdiBefore;using(var process=Process.GetCurrentProcess()){gdiBefore=GetGuiResources(process.Handle,0);}
   for(int i=0;i<30;i++){ShowWindow();await Task.Delay(35);var closed=window;CloseWindow();if(closed.HasPreview||!closed.IsDisposed)throw new InvalidOperationException("Closed preview was not released");}
   GC.Collect();GC.WaitForPendingFinalizers();long cycleGrowth=GC.GetTotalMemory(true)-cycleBefore;int gdiGrowth;using(var process=Process.GetCurrentProcess()){gdiGrowth=GetGuiResources(process.Handle,0)-gdiBefore;}
   if(cycleGrowth>4*1024*1024||gdiGrowth>8)throw new InvalidOperationException("Window cycles retained images or GDI handles");
   await Run(()=>Pet(true));await Run(()=>Pet(false));CloseWindow();
   GC.Collect();GC.WaitForPendingFinalizers();long before=GC.GetTotalMemory(true);double cpuBefore=Process.GetCurrentProcess().TotalProcessorTime.TotalMilliseconds;await Task.Delay(1300);GC.Collect();long after=GC.GetTotalMemory(true);double cpuIdle=Process.GetCurrentProcess().TotalProcessorTime.TotalMilliseconds-cpuBefore;
   var report=new {passed=window==null&&!poll.Enabled&&after-before<4*1024*1024,previewLoaded=previewLoaded,previewFileUnlocked=true,cycleManagedGrowth=cycleGrowth,cycleGdiGrowth=gdiGrowth,closedWindowReleased=window==null,hiddenPolling=poll.Enabled,idleCpuMilliseconds=cpuIdle,managedBefore=before,managedAfter=after,privateBytes=Process.GetCurrentProcess().PrivateMemorySize64};
   File.WriteAllText(receipt,new JavaScriptSerializer().Serialize(report),Encoding.UTF8);
  }catch(Exception e){File.WriteAllText(receipt,new JavaScriptSerializer().Serialize(new {passed=false,error=e.ToString()}),Encoding.UTF8);}finally{ExitThread();}
 }
}

internal static class SakuraControl {
 [STAThread]static void Main(string[] args){
  Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
  string root=Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location),receipt=null;int port=56895,parent=0;bool show=false;
  for(int i=0;i<args.Length;i++){if(args[i]=="--show")show=true;else if(args[i]=="--port"&&i+1<args.Length)port=Int32.Parse(args[++i]);else if(args[i]=="--parent"&&i+1<args.Length)parent=Int32.Parse(args[++i]);else if(args[i]=="--smoke-test"&&i+1<args.Length)receipt=Path.GetFullPath(args[++i]);}
  if(args.Length==0){
   // Direct double-click bootstraps only this local service; it never launches ChatGPT.
   var start=new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),"WindowsPowerShell\\v1.0\\powershell.exe"),"-NoProfile -ExecutionPolicy Bypass -File \""+Path.Combine(root,"start.ps1")+"\"");
   start.UseShellExecute=false;start.CreateNoWindow=true;start.WindowStyle=ProcessWindowStyle.Hidden;start.WorkingDirectory=root;
   try{using(var child=Process.Start(start)){} }catch(Exception e){MessageBox.Show(e.Message,"樱色工坊");}
   return;
  }
  if(port<1||port>65535)return;
  string identity;using(var sha=SHA256.Create()){identity=BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(root.ToLowerInvariant()))).Replace("-","");}
  bool created;using(var mutex=new Mutex(true,"Local\\SakuraStudio.Control."+identity,out created)){
   using(var signal=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\SakuraStudio.Show."+identity)){
    if(!created){if(show)signal.Set();return;}
    var context=new NativeStudioContext(root,port,signal,parent);
    if(receipt!=null){var timer=new System.Windows.Forms.Timer{Interval=100};timer.Tick+=async(s,e)=>{timer.Stop();timer.Dispose();await context.Smoke(receipt);};timer.Start();}
    else if(show)context.ShowWindow();
    Application.Run(context);
   }mutex.ReleaseMutex();
  }
 }
}
