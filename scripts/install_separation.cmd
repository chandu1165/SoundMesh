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

echo Installing Demucs for real source separation...
echo This can take several minutes because it installs PyTorch dependencies.
%PYTHON_EXE% -m pip install -U demucs
if errorlevel 1 (
  echo.
  echo Demucs installation failed.
  echo Check your internet connection and Python/pip setup, then run this script again.
  exit /b 1
)

echo.
echo Demucs installed. Now run:
echo   scripts\check_ffmpeg.cmd
echo   scripts\check_separation.cmd
echo.
echo The first actual separation may download the Demucs model weights.
endlocal
