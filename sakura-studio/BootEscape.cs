using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;

// Suppress only Escape, including its key-up. All other keys pass through untouched.
internal sealed class BootEscape : IDisposable {
  delegate IntPtr KeyboardProc(int code,IntPtr message,IntPtr data);
  [DllImport("user32.dll",SetLastError=true)] static extern IntPtr SetWindowsHookEx(int id,KeyboardProc callback,IntPtr module,uint thread);
  [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
  [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook,int code,IntPtr message,IntPtr data);
  [DllImport("kernel32.dll",CharSet=CharSet.Auto)] static extern IntPtr GetModuleHandle(string name);
  readonly KeyboardProc callback;
  readonly Dispatcher dispatcher;
  readonly Action skip;
  readonly Func<bool> enabled;
  IntPtr hook;
  bool down,armed,disposed;
  public BootEscape(Window window,Action onSkip):this(window,onSkip,()=>true){}
  public BootEscape(Window window,Action onSkip,Func<bool> canSkip){
    dispatcher=window.Dispatcher;skip=onSkip;enabled=canSkip;callback=Keyboard;
    hook=SetWindowsHookEx(13,callback,GetModuleHandle(null),0);
    if(hook==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error(),"Unable to reserve Escape for the opening");
  }
  IntPtr Keyboard(int code,IntPtr message,IntPtr data){
    if(code<0||Marshal.ReadInt32(data)!=27)return CallNextHookEx(hook,code,message,data);
    int kind=message.ToInt32();
    if(kind==0x100||kind==0x104){if(!down){down=true;armed=enabled();}}
    else if(kind==0x101||kind==0x105){
      bool fire=down&&armed;down=false;armed=false;
      // Finish after the key-up has been swallowed, so it cannot reach the restored main window.
      if(fire)dispatcher.BeginInvoke(new Action(()=>{if(!disposed&&enabled())skip();}));
    }
    return new IntPtr(1);
  }
  public void Dispose(){if(disposed)return;disposed=true;if(hook!=IntPtr.Zero){UnhookWindowsHookEx(hook);hook=IntPtr.Zero;}}
}
