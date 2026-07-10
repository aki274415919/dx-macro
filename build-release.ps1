# ============================================================
#  build-release.ps1  —  一键打发布包
#
#  产出 release\ 目录和 dx-macro-release.zip，里面自带：
#    - dx-macro.exe          自包含的程序（AHI 的 dll 已打进 exe）
#    - 安装驱动.bat           一键装 Interception 驱动（自动提权）
#    - 卸载驱动.bat
#    - Interception\          驱动安装器（脚本自动下载，不用你满世界找）
#    - 使用说明.txt
#
#  用户拿到 zip 解压即用：先跑「安装驱动.bat」重启，再运行 dx-macro.exe。
#  以后换机器就拷这个 zip，不用再下载任何东西。
#
#  用法：  pwsh -File build-release.ps1
# ============================================================
$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
Set-Location $root

$ahk   = "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
$a2e   = "C:\Program Files\AutoHotkey\Compiler\Ahk2Exe.exe"
$dlDir = Join-Path $root ".downloads"
$zipUrl = "https://github.com/oblitum/Interception/releases/download/v1.0.1/Interception.zip"
$zipSha = "AD038963D6413055765128B0B931F6E765147C9916DBA79E65D872B261F9AF10"

# ---- 1. 确保 Interception 驱动包在本地（只从官方下一次）----
New-Item -ItemType Directory -Force -Path $dlDir | Out-Null
$zip = Join-Path $dlDir "Interception.zip"
if (-not (Test-Path $zip)) {
    Write-Host "下载 Interception 驱动包（官方，仅此一次）..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zip -UseBasicParsing -TimeoutSec 120
}
$got = (Get-FileHash $zip -Algorithm SHA256).Hash
if ($got -ne $zipSha) { throw "Interception.zip 校验失败：期望 $zipSha 实得 $got" }

$ext = Join-Path $dlDir "Interception"
if (-not (Test-Path $ext)) { Expand-Archive -Path $zip -DestinationPath $ext -Force }
$installer = (Get-ChildItem $ext -Recurse -Filter "install-interception.exe" | Select-Object -First 1).FullName
if (-not $installer) { throw "解压后找不到 install-interception.exe" }

# ---- 2. 编译自包含 exe ----
# Ahk2Exe 的退出码不可靠（成功也可能非 0），所以先删旧产物，编完只认文件是否新生成。
Write-Host "编译 dx-macro.exe ..."
Remove-Item "dx-macro.exe" -Force -ErrorAction SilentlyContinue
& $a2e /in "main.ahk" /out "dx-macro.exe" /base $ahk | Out-Null
if (-not (Test-Path "dx-macro.exe")) { throw "Ahk2Exe 编译失败：没有生成 dx-macro.exe" }

# ---- 3. 组装 release\ ----
$rel = Join-Path $root "release"
if (Test-Path $rel) { Remove-Item $rel -Recurse -Force }
New-Item -ItemType Directory -Force -Path (Join-Path $rel "Interception") | Out-Null

Copy-Item "dx-macro.exe" $rel
# 发布包里放通用示例模板，不带任何人的个人配置（VID/PID、窗口名等）
$sampleDxm = @"
#Requires dx-macro
#AskAdmin on
#DxHardInput off
#PauseKey F8
#ExitKey ^!x

; 只在目标程序窗口里生效。把 target.exe 换成你的程序名（运行后按 Ctrl+Alt+W 查）。
; 不限窗口就写 #HotIf true
#HotIf WinActive("target.exe")

Numpad1::
    Send "{Down}"
    Sleep 100
    Send "{Left}"
Return
"@
[System.IO.File]::WriteAllText((Join-Path $rel "sample.dxm"), $sampleDxm, (New-Object System.Text.UTF8Encoding $false))
Copy-Item $installer (Join-Path $rel "Interception\install-interception.exe")

# 安装/卸载 bat：自动提权（内核驱动必须管理员）
$installBat = @'
@echo off
chcp 65001 >nul
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
echo 正在安装 Interception 驱动...
"%~dp0Interception\install-interception.exe" /install
echo.
echo 安装完成。请【重启电脑】后再使用 dx-macro.exe。
pause
'@
$uninstallBat = @'
@echo off
chcp 65001 >nul
net session >nul 2>&1 || (powershell -Command "Start-Process '%~f0' -Verb RunAs" & exit /b)
echo 正在卸载 Interception 驱动...
"%~dp0Interception\install-interception.exe" /uninstall
echo.
echo 卸载完成。请【重启电脑】。
pause
'@
# bat 用 GBK 存，避免中文在 cmd 里乱码（chcp 65001 已切 UTF-8，但保险起见文件本身用 UTF-8）
[System.IO.File]::WriteAllText((Join-Path $rel "安装驱动.bat"), $installBat, (New-Object System.Text.UTF8Encoding $false))
[System.IO.File]::WriteAllText((Join-Path $rel "卸载驱动.bat"), $uninstallBat, (New-Object System.Text.UTF8Encoding $false))

$readme = @"
dx-macro 使用说明
==================

普通用法（不需要驱动）：
  直接双击 dx-macro.exe。用的是 Windows 普通输入(SendInput)，绝大多数软件都吃得到。

需要驱动级输入时（目标程序读 Raw Input / DirectInput，吃不到普通输入）：
  1. 右键「安装驱动.bat」→ 以管理员身份运行（或直接双击，会自动请求管理员）。
  2. 重启电脑。
  3. 运行 dx-macro.exe，托盘菜单/脚本里开启硬输入。

配置脚本：
  编辑 sample.dxm（通用模板，照着改），或运行后按 Ctrl+Alt+E 打开内置编辑器。
  按 Ctrl+Alt+K 打开按键识别器，按任意键就知道它的名字和写法。

卸载驱动：
  右键「卸载驱动.bat」→ 以管理员运行，然后重启。

这一个文件夹就是全部，换机器整包拷过去即可，不用再下载任何东西。
"@
[System.IO.File]::WriteAllText((Join-Path $rel "使用说明.txt"), $readme, (New-Object System.Text.UTF8Encoding $false))

# ---- 4. 打 zip ----
$out = Join-Path $root "dx-macro-release.zip"
if (Test-Path $out) { Remove-Item $out -Force }
Compress-Archive -Path (Join-Path $rel "*") -DestinationPath $out

Write-Host ""
Write-Host "完成：$out"
Get-ChildItem $rel -Recurse -File | ForEach-Object { "  " + $_.FullName.Substring($rel.Length + 1) }
