@echo off
setlocal
cd /d "%~dp0\.."

if not exist "auralyze_app\build\web\index.html" (
  call scripts\build_web_deploy.cmd
  if errorlevel 1 exit /b 1
)

set AURALYZE_HOST=127.0.0.1
set AURALYZE_PORT=8788
set AURALYZE_WEB_DIR=%CD%\auralyze_app\build\web
set AI_PROVIDER=ollama
if "%OLLAMA_URL%"=="" set OLLAMA_URL=http://127.0.0.1:11434
if "%OLLAMA_MODEL%"=="" set OLLAMA_MODEL=llama3.2:3b

python backend\server.py
endlocal
