@echo off
setlocal
cd /d "%~dp0\.."

set PYTHON_EXE=python
where python >nul 2>nul
if errorlevel 1 (
  if exist "%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe" (
    set PYTHON_EXE=%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe
  )
)
for /d %%D in ("%LOCALAPPDATA%\Python\pythoncore-*") do (
  if exist "%%~fD\python.exe" set PYTHON_EXE=%%~fD\python.exe
)

if exist ".env" (
  for /f "usebackq tokens=1,* delims==" %%A in (".env") do (
    if "%%A"=="DEMUCS_COMMAND" set DEMUCS_COMMAND=%%B
  )
)

if not "%DEMUCS_COMMAND%"=="" (
  echo DEMUCS_COMMAND=%DEMUCS_COMMAND%
  %DEMUCS_COMMAND% --help >nul
  if errorlevel 1 (
    echo DEMUCS_COMMAND did not run successfully.
    exit /b 1
  )
  echo Demucs command is ready.
  exit /b 0
)

where demucs >nul 2>nul
if not errorlevel 1 (
  demucs --help >nul
  echo Demucs CLI is ready.
  exit /b 0
)

%PYTHON_EXE% -m demucs --help >nul
if errorlevel 1 (
  echo Demucs is not installed.
  echo Run scripts\install_separation.cmd, then run this check again.
  exit /b 1
)

echo Demucs Python module is ready.
endlocal
