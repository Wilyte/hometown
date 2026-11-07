# 打开地图编辑器
#   pwsh v6/tools/edit.ps1
#   pwsh v6/tools/edit.ps1 -Map my_map.json      # 新建/打开另一张图（存到 v6/data/maps/）
#   pwsh v6/tools/edit.ps1 -Shot                 # 只截一张编辑器界面（验收用）
param(
    [string]$Map = '',
    [switch]$Shot,
    [int]$W = 1400,
    [int]$H = 900,
    [string]$Godot = 'C:\Users\leo\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $proj
$env:APPDATA = Join-Path $root '.run\appdata'
New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
$shotDir = Join-Path $root '.run\v6-shots'
New-Item -ItemType Directory -Force $shotDir | Out-Null

$godotArgs = @('--path', $proj, '--resolution', "${W}x${H}", 'res://scenes/editor.tscn')
$userArgs = @()
if ($Map) { $userArgs += "--map=$Map" }
if ($Shot) {
    $out = Join-Path $shotDir 'editor.png'
    $userArgs += @('--shot', $out)
}
if ($userArgs.Count -gt 0) { $godotArgs += '--'; $godotArgs += $userArgs }
& $Godot @godotArgs
if ($Shot) { if (Test-Path (Join-Path $shotDir 'editor.png')) { "OK $(Join-Path $shotDir 'editor.png')" } else { 'FAIL 没出图' } }
