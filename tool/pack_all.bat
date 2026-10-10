@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

REM ============================================================
REM  UtaNeko: Android then Windows release packs
REM ============================================================

echo ========== pack_android ==========
call "%~dp0pack_android.bat"
if errorlevel 1 exit /b 1

echo ========== pack_windows ==========
call "%~dp0pack_windows.bat"
if errorlevel 1 exit /b 1

echo.
echo ALL OK
echo   Android: build\utaneko-release.apk
echo   Windows: build\utaneko-windows-x64.zip
echo.
exit /b 0
