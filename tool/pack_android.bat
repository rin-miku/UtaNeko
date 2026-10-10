@echo off
setlocal EnableExtensions
cd /d "%~dp0.."

REM ============================================================
REM  UtaNeko Android release APK
REM
REM  Output:
REM    build\app\outputs\flutter-apk\app-release.apk
REM    build\utaneko-release.apk
REM
REM  Dict/cache live in app private storage, not inside the APK.
REM ============================================================

call "%~dp0_pack_env.bat"
if errorlevel 1 exit /b 1

if not defined ANDROID_HOME (
  if exist "%LOCALAPPDATA%\Android\sdk" set "ANDROID_HOME=%LOCALAPPDATA%\Android\sdk"
)
if not defined ANDROID_HOME (
  if exist "D:\_Software\Android\sdk" set "ANDROID_HOME=D:\_Software\Android\sdk"
)
if defined ANDROID_HOME (
  echo ANDROID_HOME=%ANDROID_HOME%
) else (
  echo WARN: ANDROID_HOME not set; flutter will probe
)

echo.
echo [1/2] flutter build apk --release ...
call flutter build apk --release
if errorlevel 1 (
  echo ERROR: Android build failed
  exit /b 1
)

set "APK=%CD%\build\app\outputs\flutter-apk\app-release.apk"
set "COPY=%CD%\build\utaneko-release.apk"

if not exist "%APK%" (
  echo ERROR: missing %APK%
  exit /b 1
)

echo [2/2] Copy to build\utaneko-release.apk ...
copy /y "%APK%" "%COPY%" >nul
if errorlevel 1 (
  echo ERROR: copy failed
  exit /b 1
)

echo.
echo OK - Android package ready
echo   apk: %COPY%
for %%I in ("%COPY%") do echo   size: %%~zI bytes
echo.
exit /b 0
