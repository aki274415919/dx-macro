@echo off
setlocal
reg delete "HKCU\Software\Classes\.dxm" /f >nul 2>nul
reg delete "HKCU\Software\Classes\dx-macro.Script" /f >nul 2>nul
echo [ok] .dxm association removed for current user.
pause
