$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Add-Type -AssemblyName System.Drawing
Add-Type -Path (Join-Path $root 'tools/PetThinkingFrames.cs') -ReferencedAssemblies System.Drawing
$minPitch=0.0;$maxPitch=0.0
for($i=0;$i-le 100;$i++){
 $phase=$i/100.0;$arm=[PetThinkingFrames]::ArmPoint(320,390,$phase)
 if($arm.X-ne 280 -or $arm.Y-ne 390){throw 'Static arm moved'}
 $pose=[PetThinkingFrames]::ThinkingPose($phase)
 $minPitch=[Math]::Min($minPitch,$pose.Pitch);$maxPitch=[Math]::Max($maxPitch,$pose.Pitch)
 $point=[PetThinkingFrames]::HeadPoint(280,260,$phase)
 if([float]::IsNaN($point.X)-or [float]::IsNaN($point.Y)){throw 'Invalid projected point'}
}
$left=[PetThinkingFrames]::ThinkingPose(.17);$right=[PetThinkingFrames]::ThinkingPose(.47)
if($left.Yaw-ge -.15 -or $right.Yaw-le .15 -or $minPitch-ge -.06 -or $maxPitch-le .035){throw 'Missing head turn or nod: motion reduced to flat sway'}
foreach($pair in @(@(.12,.22),@(.42,.52),@(0,1))){
 $a=[PetThinkingFrames]::ThinkingPose($pair[0]);$b=[PetThinkingFrames]::ThinkingPose($pair[1])
 if([Math]::Abs($a.Yaw-$b.Yaw)+[Math]::Abs($a.Pitch-$b.Pitch)+[Math]::Abs($a.Roll-$b.Roll)-gt .00001){throw 'Hold or seamless loop boundary failed'}
}
$report=@{passed=$true;poses=101;staticArm=$true;leftYaw=$left.Yaw;rightYaw=$right.Yaw;pitchRange=@($minPitch,$maxPitch);holds=$true;loopBoundary=$true;scope='Pose curve: both turn directions, nod and lift, side holds, loop boundary and fixed arm. Visual style requires preview.'}
$report|ConvertTo-Json|Set-Content (Join-Path $root 'reports/thinking-pose-checks.json') -Encoding UTF8
$report|ConvertTo-Json -Compress
