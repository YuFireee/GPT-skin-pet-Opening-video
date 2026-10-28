param([long]$FocusHandle,[uint32]$FocusPid,[switch]$ProbeReleased,[string]$TriggerFile)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class FixtureEscape {
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h,bool altTab);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a,uint b,bool attach);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h,int id,uint modifiers,uint key);
 [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h,int id);
}
'@
if($ProbeReleased){
 if(![FixtureEscape]::RegisterHotKey([IntPtr]::Zero,197,0x4000,27)){throw 'Escape hotkey was not released'}
 $null=[FixtureEscape]::UnregisterHotKey([IntPtr]::Zero,197)
 'Escape registration released';exit
}
if($TriggerFile){
 [IO.File]::WriteAllText($TriggerFile+'.armed','armed')
 $fixtureDeadline=[DateTime]::UtcNow.AddSeconds(12)
 while(!(Test-Path -LiteralPath $TriggerFile)){
  if([DateTime]::UtcNow -gt $fixtureDeadline){throw 'Fixture trigger timed out'}
  Start-Sleep -Milliseconds 10
 }
}
$fixtureWindow=[IntPtr]$FocusHandle
$fixtureOwner=[uint32]0
$fixtureOwnerThread=[FixtureEscape]::GetWindowThreadProcessId($fixtureWindow,[ref]$fixtureOwner)
$fixtureProcess=Get-CimInstance Win32_Process -Filter ('ProcessId = '+$FocusPid)
if($fixtureOwner -ne $FocusPid -or !$fixtureProcess.CommandLine.Contains('fit-test-host.ps1')){throw 'Not the isolated fixture window'}
for($attempt=0;$attempt -lt 8;$attempt++){
 $fixtureForegroundPid=[uint32]0
 $fixtureForegroundThread=[FixtureEscape]::GetWindowThreadProcessId([FixtureEscape]::GetForegroundWindow(),[ref]$fixtureForegroundPid)
 $fixtureThread=[FixtureEscape]::GetCurrentThreadId()
 $fixtureAttached=$false
 $fixtureTargetAttached=$false
 try{
  if($fixtureForegroundThread -ne $fixtureThread){$fixtureAttached=[FixtureEscape]::AttachThreadInput($fixtureThread,$fixtureForegroundThread,$true)}
  if($fixtureForegroundThread -ne $fixtureOwnerThread){$fixtureTargetAttached=[FixtureEscape]::AttachThreadInput($fixtureForegroundThread,$fixtureOwnerThread,$true)}
  $null=[FixtureEscape]::SetWindowPos($fixtureWindow,[IntPtr](-1),0,0,0,0,0x53)
  [FixtureEscape]::SwitchToThisWindow($fixtureWindow,$true)
  $null=[FixtureEscape]::SetForegroundWindow($fixtureWindow)
 }finally{if($fixtureTargetAttached){$null=[FixtureEscape]::AttachThreadInput($fixtureForegroundThread,$fixtureOwnerThread,$false)};if($fixtureAttached){$null=[FixtureEscape]::AttachThreadInput($fixtureThread,$fixtureForegroundThread,$false)}}
 Start-Sleep -Milliseconds 80
 if([FixtureEscape]::GetForegroundWindow() -eq $fixtureWindow){break}
}
if([FixtureEscape]::GetForegroundWindow() -ne $fixtureWindow){throw 'Fixture does not own keyboard focus; no input sent'}
try{[FixtureEscape]::keybd_event(27,0,0,[UIntPtr]::Zero);Start-Sleep -Milliseconds 55}
finally{[FixtureEscape]::keybd_event(27,0,2,[UIntPtr]::Zero)}
'Escape pressed while isolated fixture held focus'
