$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:config=@{readinessMode='native-window'}
. (Join-Path $root 'sakura-studio/quota-pet/runtime/host-ready.ps1')
$script:hostHandle=[IntPtr]101;$script:lastHostProbe=0;$script:lastPosition='old';$script:probes=0
if(!(Update-WidgetHostCandidate $false 1000 {$script:probes++;[IntPtr]202})){throw 'A hidden but valid host blocked replacement.'}
if($script:hostHandle-ne [IntPtr]202 -or $null-ne $script:lastPosition){throw 'Replacement did not reset placement.'}
if(Update-WidgetHostCandidate $false 1500 {$script:probes++;[IntPtr]303}){throw 'Host discovery was not throttled.'}
if($script:probes-ne 1){throw 'Repeated native scan inside one second.'}
if(Update-WidgetHostCandidate $true 2500 {$script:probes++;[IntPtr]303}){throw 'Visible host changed unnecessarily.'}
if(Update-WidgetHostCandidate $false 3000 {$script:probes++;[IntPtr]::Zero}){throw 'Missing candidate reported a replacement.'}
if($script:hostHandle-ne [IntPtr]202){throw 'Hidden host forgotten before it could resume.'}
$receipt=Join-Path $root 'reports/pet-visibility-fixture.json';[IO.Directory]::CreateDirectory((Split-Path -Parent $receipt))|Out-Null
$script:writes=0
function Write-WidgetJson($Path,$Value){$script:writes++;[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json),[Text.UTF8Encoding]::new($false))}
foreach($visible in @($false,$false,$true,$true,$false,$false,$true)){
 Publish-WidgetVisibility $receipt $visible
 $state=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
 if($state.shown-ne $visible -or ($state.state-eq 'ready')-ne $visible){throw 'Visibility receipt stayed stale after a transition.'}
}
if($script:writes-ne 4){throw 'Unchanged visibility kept writing to disk.'}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'sakura-studio/quota-pet/widget.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Widget syntax error.'}
# Compile the real HWND helper, including the cloaked/minimized host checks.
$source=$ast.Find({param($node)$node -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Value.Contains('public static class GptWidgetNative')},$true)
if(!$source){throw 'Native host helper missing.'};Add-Type -TypeDefinition $source.Value
@{passed=$true;hiddenHostReplacement=$true;probeThrottled=$true;missingHostCanResume=$true;visibilityTransitions=4;unchangedStateWrites=0;nativeHelperCompiled=$true;scope='Host selection and visibility receipt fixtures; no real application or account CLI launched.'}|ConvertTo-Json
