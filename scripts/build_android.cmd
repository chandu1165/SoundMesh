@echo off
setlocal
cd /d "%~dp0\..\auralyze_app"

if not exist "android" (
  echo Creating Android platform files...
  call flutter create --platforms=android .
  if errorlevel 1 exit /b 1
)

call flutter build apk --debug
if errorlevel 1 exit /b 1

echo Android APK ready at auralyze_app\build\app\outputs\flutter-apk\app-debug.apk
endlocal
