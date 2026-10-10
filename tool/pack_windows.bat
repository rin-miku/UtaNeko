@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

REM ============================================================
REM  UtaNeko Windows release pack
REM
REM  Output:
REM    build\windows\x64\runner\Release\utaneko.exe
REM    build\utaneko-windows-x64.zip
REM
REM  IMPORTANT:
REM    Dictionaries / furi cache live in exe-side utaneko-data\
REM    (portable app data). The zip MUST exclude utaneko-data.
REM    Local Release\utaneko-data is kept for continued testing.
REM ============================================================

call "%~dp0_pack_env.bat"
if errorlevel 1 exit /b 1

echo.
echo [1/4] Kill running utaneko.exe if any...
taskkill /F /IM utaneko.exe >nul 2>&1

echo [2/4] flutter build windows --release ...
call flutter build windows --release
if errorlevel 1 (
  echo ERROR: Windows build failed
  exit /b 1
)

set "OUT=%CD%\build\windows\x64\runner\Release"
set "STAGE=%CD%\build\pack-windows-staging"
set "ZIP=%CD%\build\utaneko-windows-x64.zip"

if not exist "%OUT%\utaneko.exe" (
  echo ERROR: missing %OUT%\utaneko.exe
  exit /b 1
)

echo [3/4] Stage release files excluding utaneko-data...
if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%"
if errorlevel 1 exit /b 1
robocopy "%OUT%" "%STAGE%" /E /XD utaneko-data /NFL /NDL /NJH /NJS /nc /ns /np >nul
set "RC=%ERRORLEVEL%"
if %RC% GEQ 8 (
  echo ERROR: robocopy failed, code=%RC%
  exit /b 1
)

if exist "%STAGE%\utaneko-data" (
  echo ERROR: staging still contains utaneko-data, abort
  exit /b 1
)

echo [4/4] Write zip...
if exist "%ZIP%" del /f /q "%ZIP%"
powershell -NoProfile -Command "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%ZIP%' -Force"
if errorlevel 1 (
  echo ERROR: zip failed
  exit /b 1
)

rmdir /s /q "%STAGE%"

echo.
echo OK - Windows package ready
echo   exe: %OUT%\utaneko.exe
echo   zip: %ZIP%
for %%I in ("%ZIP%") do echo   size: %%~zI bytes
echo.
exit /b 0
