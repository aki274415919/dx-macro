@echo off
setlocal
set "EXE=%~dp0dx-macro.exe"

if not exist "%EXE%" (
    echo [x] Cannot find dx-macro.exe beside this script.
    echo     Build or copy dx-macro.exe here first.
    pause
    exit /b 1
)

reg add "HKCU\Software\Classes\.dxm" /ve /d "dx-macro.Script" /f >nul
reg add "HKCU\Software\Classes\dx-macro.Script" /ve /d "dx-macro script" /f >nul
reg add "HKCU\Software\Classes\dx-macro.Script\DefaultIcon" /ve /d "\"%EXE%\",0" /f >nul
reg add "HKCU\Software\Classes\dx-macro.Script\shell\open\command" /ve /d "\"%EXE%\" \"%%1\"" /f >nul

echo [ok] .dxm is now associated with:
echo      %EXE%
echo.
echo You can now double-click .dxm files.
pause
