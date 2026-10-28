import {sourceRoot,reportsRoot} from './runtime.mjs';
import fs from 'node:fs/promises';import path from 'node:path';import {execFileSync} from 'node:child_process';import assert from 'node:assert/strict';
const bridge=path.join(sourceRoot,'native-bridge.ps1').replaceAll("'","''");
const fixture=path.join(reportsRoot,'tray-relaunch-fixture.ps1');
await fs.writeFile(fixture,`﻿param([string]$Scenario)
$ErrorActionPreference='Stop';$global:probes=0;$global:launches=0
function Get-Process {param($Name,$ErrorAction) @()}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) @()}
function Get-NetTCPConnection {param($LocalPort,$State,$ErrorAction)
 $global:probes++;if($Scenario -eq 'persistent' -or $global:probes -le 3){[pscustomobject]@{LocalAddress='127.0.0.1';OwningProcess=12345}}
}
function Get-AppxPackage {param($Name) [pscustomobject]@{InstallLocation=$PSScriptRoot;PublisherId='fixture'}}
function Test-Path {param($LiteralPath,$PathType) $true}
function New-Item {param($ItemType,$Path,[switch]$Force)}
function Start-Process {param($FilePath,$ArgumentList,$WindowStyle) $global:launches++}
$action=if($Scenario -eq 'inspect'){'Inspect'}else{'LaunchBackground'}
$result=& '${bridge}' -Action $action -Profile (Join-Path $PSScriptRoot 'fake-profile')
[pscustomobject]@{result=($result|ConvertFrom-Json);launches=$global:launches;probes=$global:probes}|ConvertTo-Json -Depth 5 -Compress
`);
const results=[];
for(const mode of ['transient','persistent','inspect']){
 const d=JSON.parse(execFileSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',fixture,mode],{encoding:'utf8',windowsHide:true,timeout:15000}).trim());
 assert.equal(d.launches,mode==='transient'?1:0);if(mode==='inspect')assert.equal(d.probes,1);else assert(d.probes<=8);results.push({mode,launches:d.launches,probes:d.probes});
}
await fs.writeFile(path.join(reportsRoot,'tray-relaunch-checks.json'),JSON.stringify({passed:true,results,scope:'Mocked native process/port queries and launch; no real app invoked'},null,2));console.log(JSON.stringify({passed:true,results}));


