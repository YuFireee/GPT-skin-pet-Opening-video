$ErrorActionPreference='Stop'
$pet=Join-Path $PSScriptRoot 'quota-pet'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
$snippets=@()
foreach($name in @('widget.ps1','runtime/host-layer.ps1','runtime/host-follow.ps1')){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $pet $name),[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('Cannot parse pet source: '+$name)}
 foreach($node in $ast.FindAll({param($a)$a -is [Management.Automation.Language.StringConstantExpressionAst] -and $a.StringConstantType-eq 'SingleQuotedHereString'},$true)){
  if($node.Value -match 'public (static class GptWidgetNative|sealed class GptBezierEase|static class GptWidgetZOrderNative|sealed class GptWidgetHostFollower)'){$snippets+=$node.Value}
 }
}
if($snippets.Count-ne 4){throw 'Expected four native pet helper definitions.'}
foreach($name in @('IdleSpritePlayer.cs','PanelMorph.cs')){$snippets+=[IO.File]::ReadAllText((Join-Path $pet ('runtime/'+$name)))}
$pattern='\busing\s+([\w.]+)\s*;'
$namespaces=@(foreach($snippet in $snippets){foreach($match in [regex]::Matches($snippet,$pattern)){$match.Groups[1].Value}})|Sort-Object -Unique
$source=(@($namespaces|ForEach-Object {'using '+$_+';'})+@($snippets|ForEach-Object {[regex]::Replace($_,$pattern,'')}))-join "`r`n"
$output=Join-Path $pet 'runtime/WidgetNative.dll'
if(Test-Path -LiteralPath $output){Remove-Item -LiteralPath $output -Force}
Add-Type -TypeDefinition $source -OutputAssembly $output -ReferencedAssemblies ([Windows.Window].Assembly.Location),([Windows.Media.Animation.AnimationTimeline].Assembly.Location),([Windows.Freezable].Assembly.Location),([Windows.Markup.IQueryAmbient].Assembly.Location)
