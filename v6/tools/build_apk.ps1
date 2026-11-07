# 出 Android APK（debug 签名，arm64-v8a，包名 hometown.wulie.tech）
#   pwsh v6/tools/build_apk.ps1
# 产物：dist/hometown-android-v6.apk（同时打印体积与 md5）
param(
    [string]$Out = 'dist/hometown-android-v6.apk',
    [string]$Godot = 'C:\Users\leo\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot          # v6
$root = Split-Path -Parent $proj                   # 仓库根
$env:APPDATA = Join-Path $root '.run\appdata'      # 里面要有 export_templates 和 editor_settings（debug.keystore）
New-Item -ItemType Directory -Force $env:APPDATA, (Join-Path $root 'dist') | Out-Null

$apk = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $root $Out }
if (Test-Path $apk) { Remove-Item $apk -Force }

Write-Host "== import"
& $Godot --headless --path $proj --import *> (Join-Path $root '.run\v6-shots\import.log')

Write-Host "== export"
& $Godot --headless --path $proj --export-debug "Android" $apk *> (Join-Path $root '.run\v6-shots\export.log')
if (-not (Test-Path $apk)) { Write-Host "FAIL 见 .run/v6-shots/export.log"; Get-Content (Join-Path $root '.run\v6-shots\export.log') -Tail 15; exit 1 }

$f = Get-Item $apk
$md5 = (Get-FileHash $apk -Algorithm MD5).Hash.ToUpper()
"OK {0}  {1:N2} MB  md5={2}" -f $apk, ($f.Length / 1MB), $md5
