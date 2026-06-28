@echo off
setlocal
cd /d "%~dp0\..\auralyze_app"

if not exist "windows" (
  echo Creating Windows platform files...
  call flutter create --platforms=windows .
  if errorlevel 1 exit /b 1
)

call flutter build windows
if errorlevel 1 exit /b 1

echo Windows build ready at auralyze_app\build\windows\x64\runner\Release
endlocal
