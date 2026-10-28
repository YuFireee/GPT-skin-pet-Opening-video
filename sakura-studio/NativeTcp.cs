using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Net;
using System.Runtime.InteropServices;

public sealed class SakuraTcpListener {
 public string LocalAddress {get;set;}
 public int LocalPort {get;set;}
 public uint OwningProcess {get;set;}
}
public static class SakuraTcp {
 [DllImport("iphlpapi.dll",SetLastError=true)]static extern uint GetExtendedTcpTable(IntPtr table,ref int size,bool order,int family,int tableClass,uint reserved);
 static int Port(uint value){return (int)(((value&255)<<8)|((value>>8)&255));}
 public static SakuraTcpListener[] Listeners(int port){
  if(port<1||port>65535)throw new ArgumentOutOfRangeException("port");
  var result=new List<SakuraTcpListener>();Read(result,port,2);Read(result,port,23);return result.ToArray();
 }
 static void Read(List<SakuraTcpListener> result,int port,int family){
  int size=0;uint error=GetExtendedTcpTable(IntPtr.Zero,ref size,false,family,3,0);
  if(error==50&&family==23)return; // IPv6 is unavailable on this system.
  if(error!=0&&error!=122)throw new Win32Exception((int)error);
  for(int attempt=0;attempt<4;attempt++){
   IntPtr buffer=Marshal.AllocHGlobal(size);
   try{
    int available=size;error=GetExtendedTcpTable(buffer,ref size,false,family,3,0);
    if(error==122)continue;
    if(error!=0)throw new Win32Exception((int)error);
    int rows=Marshal.ReadInt32(buffer),rowSize=family==2?24:56;
    if(rows<0||4L+(long)rows*rowSize>available)throw new InvalidOperationException("Invalid TCP table length");
    for(int i=0;i<rows;i++){
     IntPtr row=IntPtr.Add(buffer,4+i*rowSize);int portOffset=family==2?8:20;
     int localPort=Port(unchecked((uint)Marshal.ReadInt32(row,portOffset)));if(localPort!=port)continue;
     string address;
     if(family==2)address=new IPAddress(unchecked((uint)Marshal.ReadInt32(row,4))).ToString();
     else{var bytes=new byte[16];Marshal.Copy(row,bytes,0,16);address=new IPAddress(bytes,unchecked((uint)Marshal.ReadInt32(row,16))).ToString();}
     result.Add(new SakuraTcpListener{LocalAddress=address,LocalPort=localPort,OwningProcess=unchecked((uint)Marshal.ReadInt32(row,family==2?20:52))});
    }
    return;
   }finally{Marshal.FreeHGlobal(buffer);}
  }
  throw new InvalidOperationException("TCP table kept changing; inspection stopped");
 }
}
