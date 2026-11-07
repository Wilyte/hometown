# 光照/颜色标定：跑一遍 calib 场景并把中心像素读数打出来
#   pwsh v6/tools/calib.ps1
# 产物落 <repo>/.run/v6-shots/calib_*.png
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot
$root = Split-Path -Parent $proj
$env:APPDATA = Join-Path $root '.run\appdata'
$shotDir = Join-Path $root '.run\v6-shots'
New-Item -ItemType Directory -Force $env:APPDATA, $shotDir | Out-Null
Get-ChildItem $shotDir -Filter 'calib_*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
& 'C:\Users\leo\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe' `
    --path $proj --resolution 320x240 --disable-vsync -- `
    --calib-dir=$shotDir res://tools/calib.tscn *> (Join-Path $shotDir 'calib.log')
Get-Content (Join-Path $shotDir 'calib.log') | Select-String 'CALIB' | Select-Object -Last 8
python (Join-Path $PSScriptRoot 'read_calib.py') $shotDir
