# 出 Web（HTML5 / WebAssembly）构建，产物是纯静态文件，落在 dist/web/。
#   pwsh v6/tools/build_web.ps1
#   pwsh v6/tools/build_web.ps1 -Out dist/web-preview
# 预览：python v6/tools/serve_web.py      → http://127.0.0.1:5173
#
# 说明：
#   · 浏览器只能用 gl_compatibility（WebGL2），Web 平台默认就是它，不用改 project.godot。
#   · assets/parts/ 是拆件器生成物（gitignore），克隆下来第一次构建会自动跑一遍。
#   · 模板里默认 variant/thread_support=false，普通静态托管即可，不需要 COOP/COEP；
#     要开线程就在 export_presets.cfg 里改 true，并用 serve_web.py（已带这两个头）。
param(
    [string]$Out = 'dist/web',
    [string]$Godot = 'C:\Users\leo\tools\godot\4.7.2\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$proj = Split-Path -Parent $PSScriptRoot          # v6
$root = Split-Path -Parent $proj                   # 仓库根
$env:APPDATA = Join-Path $root '.run' 'appdata'    # 里面要有 export_templates
New-Item -ItemType Directory -Force $env:APPDATA, (Join-Path $root 'dist') | Out-Null
$logDir = Join-Path $root '.run' 'v6-shots'
New-Item -ItemType Directory -Force $logDir | Out-Null

$web = if ([System.IO.Path]::IsPathRooted($Out)) { $Out } else { Join-Path $root $Out }
if (Test-Path $web) { Remove-Item $web -Recurse -Force }
New-Item -ItemType Directory -Force $web | Out-Null

Write-Host "== import"
& $Godot --headless --path $proj --import *> (Join-Path $logDir 'web-import.log')

$parts = Join-Path $proj 'assets' 'parts'
if (-not (Test-Path $parts) -or @(Get-ChildItem $parts -Filter *.tscn -ErrorAction SilentlyContinue).Count -eq 0) {
    Write-Host "== split parts（第一次构建，生成 assets/parts）"
    & $Godot --headless --path $proj -s res://tools/split_parts.gd *> (Join-Path $logDir 'web-parts.log')
    if (@(Get-ChildItem $parts -Filter *.tscn -ErrorAction SilentlyContinue).Count -eq 0) {
        Write-Host "FAIL 拆件器没生成 part，见 .run/v6-shots/web-parts.log"
        Get-Content (Join-Path $logDir 'web-parts.log') -Tail 15
        exit 1
    }
}

Write-Host "== export Web"
$html = Join-Path $web 'index.html'
& $Godot --headless --path $proj --export-release "Web" $html *> (Join-Path $logDir 'web-export.log')
if (-not (Test-Path $html)) {
    Write-Host "FAIL 见 .run/v6-shots/web-export.log"
    Get-Content (Join-Path $logDir 'web-export.log') -Tail 20
    exit 1
}

$files = @(Get-ChildItem $web -File)
$mb = ($files | Measure-Object Length -Sum).Sum / 1MB
"OK {0}  {1} files  {2:N2} MB" -f $web, $files.Count, $mb
$files | Sort-Object Length -Descending | Select-Object -First 6 |
    ForEach-Object { "  {0,-20} {1,8:N2} MB" -f $_.Name, ($_.Length / 1MB) }
Write-Host "预览：python v6/tools/serve_web.py"
