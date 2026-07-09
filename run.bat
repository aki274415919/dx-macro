@echo off
rem 绿色版启动器：优先用本文件夹里的 AutoHotkey64.exe，其次用已安装的 v2
setlocal
set "AHK=%~dp0AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK%" set "AHK=%LOCALAPPDATA%\Programs\AutoHotkey\v2\AutoHotkey64.exe"

if not exist "%AHK%" (
    echo [x] 找不到 AutoHotkey v2 解释器。
    echo     绿色版做法: 从 https://www.autohotkey.com/download/ 下载 v2 zip,
    echo     把 AutoHotkey64.exe 复制到本文件夹后重新运行 run.bat
    pause
    exit /b 1
)

"%AHK%" "%~dp0main.ahk"
