@echo off
setlocal
cd /d "%~dp0\.."

set DIST=dist\auralyze_product
set PYTHON_EXE=python
where python >nul 2>nul
if errorlevel 1 (
  if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
    set PYTHON_EXE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe
  )
)

if exist "auralyze_app\build\web\index.html" (
  echo Using existing Flutter web build.
) else (
  echo Building Flutter web...
  pushd auralyze_app
  call flutter build web
  if errorlevel 1 exit /b 1
  popd
)

echo Creating package folder %DIST%...
if exist "%DIST%" rmdir /s /q "%DIST%"
mkdir "%DIST%"
mkdir "%DIST%\backend"
mkdir "%DIST%\web"
mkdir "%DIST%\scripts"

xcopy /e /i /y "auralyze_app\build\web" "%DIST%\web" >nul
xcopy /e /i /y "backend" "%DIST%\backend" >nul
xcopy /e /i /y "scripts" "%DIST%\scripts" >nul
if exist "%DIST%\backend\data" rmdir /s /q "%DIST%\backend\data"
if exist "%DIST%\backend\__pycache__" rmdir /s /q "%DIST%\backend\__pycache__"
if exist "%DIST%\scripts\__pycache__" rmdir /s /q "%DIST%\scripts\__pycache__"
copy /y "README.md" "%DIST%\README.md" >nul
copy /y "deployment.md" "%DIST%\deployment.md" >nul
copy /y "Dockerfile" "%DIST%\Dockerfile" >nul
copy /y ".dockerignore" "%DIST%\.dockerignore" >nul
copy /y "render.yaml" "%DIST%\render.yaml" >nul
copy /y ".env.example" "%DIST%\.env.example" >nul

(
  echo @echo off
  echo setlocal
  echo cd /d "%%~dp0"
  echo if "%%AI_PROVIDER%%"=="" set AI_PROVIDER=ollama
  echo if "%%OLLAMA_URL%%"=="" set OLLAMA_URL=http://127.0.0.1:11434
  echo if "%%OLLAMA_MODEL%%"=="" set OLLAMA_MODEL=llama3.2:3b
  echo set PYTHON_EXE=python
  echo where python ^>nul 2^>nul
  echo if errorlevel 1 set PYTHON_EXE=%PYTHON_EXE%
  echo start "Auralyze Backend" cmd /k %%PYTHON_EXE%% backend\server.py
  echo start "Auralyze Web" cmd /k "cd /d web ^&^& %%PYTHON_EXE%% -m http.server 8791 --bind 127.0.0.1"
  echo echo Open http://127.0.0.1:8791/index.html
  echo echo Free AI mode uses Ollama when running, otherwise local DSP/OKF rules.
  echo endlocal
) > "%DIST%\start_auralyze.cmd"

echo.
echo Package ready: %DIST%
echo Run %DIST%\start_auralyze.cmd on this machine.
endlocal
