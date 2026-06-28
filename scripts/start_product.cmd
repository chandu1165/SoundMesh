@echo off
setlocal
cd /d "%~dp0\.."

if "%AI_PROVIDER%"=="" set AI_PROVIDER=ollama
if "%OLLAMA_URL%"=="" set OLLAMA_URL=http://127.0.0.1:11434
if "%OLLAMA_MODEL%"=="" set OLLAMA_MODEL=llama3.2:3b
set PYTHON_EXE=python
where python >nul 2>nul
if errorlevel 1 (
  if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
    set PYTHON_EXE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe
  )
)

echo Starting Auralyze backend on http://127.0.0.1:8788
start "Auralyze Backend" cmd /k %PYTHON_EXE% backend\server.py

echo Starting Flutter web build on http://127.0.0.1:8791
start "Auralyze Web" cmd /k "cd /d auralyze_app\build\web && %PYTHON_EXE% -m http.server 8791 --bind 127.0.0.1"

echo.
echo Open http://127.0.0.1:8791/index.html
echo Free AI mode:
echo   Auralyze uses Ollama if it is running, otherwise local DSP/OKF rules.
echo   To enable the local model, install Ollama and run:
echo     ollama pull %OLLAMA_MODEL%
endlocal
