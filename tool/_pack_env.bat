@echo off
REM Shared by pack_*.bat: locate flutter on PATH.

where flutter >nul 2>&1
if not errorlevel 1 goto :ok

if exist "D:\_Software\flutter\bin\flutter.bat" (
  set "PATH=D:\_Software\flutter\bin;%PATH%"
  goto :ok
)

if exist "%LOCALAPPDATA%\flutter\bin\flutter.bat" (
  set "PATH=%LOCALAPPDATA%\flutter\bin;%PATH%"
  goto :ok
)

echo ERROR: flutter not found. Add flutter\bin to PATH or install at D:\_Software\flutter
exit /b 1

:ok
REM flutter is a .bat: must use call, else parent script exits early
call flutter --version
exit /b 0
