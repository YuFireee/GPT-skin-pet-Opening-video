$script:resourceSamples=[Collections.Generic.Queue[object]]::new()
$script:lastResourceSample=0L;$script:resourceBreaches=0;$script:resourceStopped=$false
function Test-WidgetMemoryLimit([double]$PrivateMB,[double]$LimitMB){
  if($LimitMB -gt 0 -and $PrivateMB -gt $LimitMB){$script:resourceBreaches++}else{$script:resourceBreaches=0}
  return $script:resourceBreaches -ge 3
}
function Tick-WidgetResources([long]$Now){
  if($Now-$script:lastResourceSample -lt 30000){return};$script:lastResourceSample=$Now
  $process=[Diagnostics.Process]::GetCurrentProcess()
  try{$sample=@{at=$Now;privateMB=[Math]::Round($process.PrivateMemorySize64/1MB,1);workingMB=[Math]::Round($process.WorkingSet64/1MB,1);handles=$process.HandleCount;managedMB=[Math]::Round([GC]::GetTotalMemory($false)/1MB,1);gen0=[GC]::CollectionCount(0);gen1=[GC]::CollectionCount(1);gen2=[GC]::CollectionCount(2)}}finally{$process.Dispose()}
  $script:resourceSamples.Enqueue($sample);while($script:resourceSamples.Count -gt 60){$null=$script:resourceSamples.Dequeue()}
  $limit=if($script:config.readinessMode -eq 'native-window'){512}else{0}
  $script:resourceStopped=Test-WidgetMemoryLimit $sample.privateMB $limit
  Write-WidgetJson (Join-Path $script:dataDir 'resource-health.json') @{samples=@($script:resourceSamples.ToArray());limitMB=$limit;paused=$script:resourceStopped}
  if($script:resourceStopped){$script:window.Close()}
}
