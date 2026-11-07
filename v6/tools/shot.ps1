# 出静帧（沿用 .run/hd3d-ref/tools 的取证思路，这里由脚本自己存图）
#   pwsh v6/tools/shot.ps1
#   pwsh v6/tools/shot.ps1 -W 1672 -H 941 -Out .run/v6-shots/kit-16x9.png
# 产物一律落在 <repo>/.run/v6-shots/，不污染工程目录。
param(
    [string]$Out = '',
    [int]$W = 1246,
    [int]$H = 956,
    [string]$Look = '',
    [switch]$DumpShadow,
    [switch]$NoActors,
    [string]$Godot = 'C:\Users\leo\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $proj
$env:APPDATA = Join-Path $root '.run\appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$shotDir = Join-Path $root '.run\v6-shots'
New-Item -ItemType Directory -Force $shotDir | Out-Null

if (-not $Out) { $Out = Join-Path $shotDir 'kit.png' }
elseif (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path $root $Out }
New-Item -ItemType Directory -Force (Split-Path -Parent $Out) | Out-Null
if (Test-Path $Out) { Remove-Item $Out -Force }

$userArgs = @('--shot', $Out)
if ($NoActors) { $userArgs += '--no-actors' }
if ($Look) { $userArgs += "--look=res://$Look" }
if ($DumpShadow) { $userArgs += "--dump-shadow=$(Join-Path $shotDir 'shadow_mask.png')" }

& $Godot --path $proj --resolution "${W}x${H}" --disable-vsync -- @userArgs *> (Join-Path $shotDir 'run.log')
if (Test-Path $Out) { "OK $Out"; Get-Content (Join-Path $shotDir 'run.log') | Select-String 'KIT|CAM|SHADOW|MATS|SHOT' } else { "FAIL 见 $(Join-Path $shotDir 'run.log')"; exit 1 }
