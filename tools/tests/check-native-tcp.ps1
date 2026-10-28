$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Add-Type -Path (Join-Path $root 'sakura-studio/NativeTcp.dll')
$ipv4=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$ipv6=$null
try{
 $ipv4.Start();$port=$ipv4.LocalEndpoint.Port
 $watch=[Diagnostics.Stopwatch]::StartNew();$rows=@([SakuraTcp]::Listeners($port));$watch.Stop();$nativeMs=$watch.Elapsed.TotalMilliseconds
 $own=@($rows|Where-Object {$_.LocalAddress-eq '127.0.0.1' -and $_.OwningProcess-eq $PID})
 if($own.Count-ne 1 -or $own[0].LocalPort-ne $port){throw 'IPv4 listener identity differs.'}
 $watch.Restart();$reference=@(Get-NetTCPConnection -LocalPort $port -State Listen);$watch.Stop();$cmdletMs=$watch.Elapsed.TotalMilliseconds
 if($reference[0].OwningProcess-ne $own[0].OwningProcess -or $reference[0].LocalAddress-ne $own[0].LocalAddress){throw 'Native TCP result differs from Windows cmdlet.'}
 $testedV6=$false
 if([Net.Sockets.Socket]::OSSupportsIPv6){$ipv6=[Net.Sockets.TcpListener]::new([Net.IPAddress]::IPv6Loopback,0);$ipv6.Start();$rows=@([SakuraTcp]::Listeners($ipv6.LocalEndpoint.Port));if(!@($rows|Where-Object {$_.LocalAddress-eq '::1' -and $_.OwningProcess-eq $PID}).Count){throw 'IPv6 identity differs.'};$testedV6=$true}
 $ipv4.Stop();if(@([SakuraTcp]::Listeners($port)).Count){throw 'Closed listener remained in native snapshot.'}
 $report=@{passed=$true;ipv4OwnerVerified=$true;ipv6OwnerVerified=$testedV6;matchesWindowsCmdlet=$true;nativeMilliseconds=[math]::Round($nativeMs,2);cmdletMilliseconds=[math]::Round($cmdletMs,2);scope='Own short-lived loopback listeners only; no application launch or remote connection.'}
 $report|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'reports/native-tcp-checks.json') -Encoding UTF8
 $report|ConvertTo-Json
}finally{$ipv4.Stop();if($ipv6){$ipv6.Stop()}}
