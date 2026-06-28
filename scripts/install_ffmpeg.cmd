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

echo Installing imageio-ffmpeg...
%PYTHON_EXE% -m pip install -U imageio-ffmpeg
if errorlevel 1 (
  echo.
  echo FFmpeg package installation failed.
  echo Check your internet connection and Python/pip setup, then run this script again.
  exit /b 1
)

echo.
echo FFmpeg executable:
%PYTHON_EXE% -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())"
echo.
echo Run scripts\check_ffmpeg.cmd to verify.
endlocal
