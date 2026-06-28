@echo off
setlocal
cd /d "%~dp0\..\auralyze_app"

if "%AURALYZE_BACKEND_URL%"=="" (
  echo Building Flutter web for same-origin deployment.
  call flutter build web --release --dart-define=AURALYZE_BACKEND_URL=
) else (
  echo Building Flutter web for backend:
  echo   %AURALYZE_BACKEND_URL%
  call flutter build web --release --dart-define=AURALYZE_BACKEND_URL=%AURALYZE_BACKEND_URL%
)

if errorlevel 1 exit /b 1
echo Web build ready at auralyze_app\build\web
endlocal
