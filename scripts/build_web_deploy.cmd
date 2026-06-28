@echo off
setlocal
cd /d "%~dp0\..\auralyze_app"

set AUTH_DEFINES=--dart-define=AURALYZE_AUTH_MODE=%AURALYZE_AUTH_MODE% --dart-define=AURALYZE_FIREBASE_API_KEY=%AURALYZE_FIREBASE_API_KEY% --dart-define=AURALYZE_FIREBASE_PROJECT_ID=%AURALYZE_FIREBASE_PROJECT_ID%

if "%AURALYZE_BACKEND_URL%"=="" (
  echo Building Flutter web for same-origin deployment.
  call flutter build web --release --dart-define=AURALYZE_BACKEND_URL= %AUTH_DEFINES%
) else (
  echo Building Flutter web for backend:
  echo   %AURALYZE_BACKEND_URL%
  call flutter build web --release --dart-define=AURALYZE_BACKEND_URL=%AURALYZE_BACKEND_URL% %AUTH_DEFINES%
)

if errorlevel 1 exit /b 1
echo Web build ready at auralyze_app\build\web
endlocal
