# 跑起来（左键拖动环绕、滚轮缩放、方向键/+- 也可以、R 复位）
#   pwsh v6/tools/run.ps1
param(
    [int]$W = 1246,
    [int]$H = 956,
    [string]$Godot = 'C:\Users\leo\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $proj
$env:APPDATA = Join-Path $root '.run\appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
& $Godot --path $proj --resolution "${W}x${H}"
