# 装到手机并拉起（默认 vivo V2458A）
#   pwsh v6/tools/install_apk.ps1
#   pwsh v6/tools/install_apk.ps1 -Apk dist/hometown-android-v6.apk -Reinstall
# 说明：同包名但签名不同（例如之前装过 v3）会 INSTALL_FAILED_UPDATE_INCOMPATIBLE，
#       -Reinstall 会先卸载旧包（会清掉旧包数据）。
param(
    [string]$Apk = 'dist/hometown-android-v6.apk',
    [switch]$Reinstall,
    [string]$Adb = 'C:\Users\leo\Linux\adb_fastboot\adb.exe',
    [string]$Package = 'hometown.wulie.tech'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$apkPath = if ([System.IO.Path]::IsPathRooted($Apk)) { $Apk } else { Join-Path $root $Apk }
if (-not (Test-Path $apkPath)) { throw "没有 APK：$apkPath" }

$devices = (& $Adb devices) -join "`n"
if ($devices -notmatch "device$") { throw "没有连着的手机（adb devices 为空）" }

if ($Reinstall) {
    Write-Host "== 卸载旧包 $Package"
    & $Adb uninstall $Package 2>&1 | Out-Null
}
Write-Host "== 安装 $apkPath"
$out = & $Adb install -r $apkPath 2>&1
$out | Select-Object -Last 3
if ($out -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
    Write-Host "签名不一致：加 -Reinstall 重跑（会卸载旧包）"
    exit 2
}
if ($out -notmatch "Success") { exit 1 }

Write-Host "== 拉起"
& $Adb shell am force-stop $Package 2>&1 | Out-Null
& $Adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 2>&1 | Out-Null
Start-Sleep -Seconds 10

$shot = Join-Path $root '.run\v6-shots\phone.png'
& $Adb shell screencap -p /sdcard/v6shot.png
& $Adb pull /sdcard/v6shot.png $shot 2>&1 | Out-Null
& $Adb shell rm /sdcard/v6shot.png | Out-Null
"OK 截图 {0}" -f $shot
